// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const lp = @import("lightpanda");
const builtin = @import("builtin");
const milliTimestamp = @import("../../datetime.zig").milliTimestamp;

const log = lp.log;
const IS_DEBUG = builtin.mode == .Debug;

const Queue = std.PriorityQueue(Task, void, struct {
    fn compare(_: void, a: Task, b: Task) std.math.Order {
        const time_order = std.math.order(a.run_at, b.run_at);
        if (time_order != .eq) return time_order;
        // Break ties with sequence number to maintain FIFO order
        return std.math.order(a.sequence, b.sequence);
    }
}.compare);

const Scheduler = @This();

_sequence: u64,
low_priority: Queue,
high_priority: Queue,
run_high_first: bool,

pub fn init(allocator: std.mem.Allocator) Scheduler {
    return .{
        ._sequence = 0,
        .low_priority = Queue.init(allocator, {}),
        .high_priority = Queue.init(allocator, {}),
        .run_high_first = false,
    };
}

pub fn deinit(self: *Scheduler) void {
    finalizeTasks(&self.low_priority);
    finalizeTasks(&self.high_priority);
}

pub fn reset(self: *Scheduler) void {
    finalizeTasks(&self.low_priority);
    finalizeTasks(&self.high_priority);
    self.low_priority.clearRetainingCapacity();
    self.high_priority.clearRetainingCapacity();
    self.run_high_first = false;
}

const AddOpts = struct {
    name: []const u8 = "",
    low_priority: bool = false,
    finalizer: ?Finalizer = null,
};
pub fn add(self: *Scheduler, ctx: *anyopaque, cb: Callback, run_in_ms: u32, opts: AddOpts) !void {
    if (comptime IS_DEBUG) {
        log.debug(.scheduler, "scheduler.add", .{ .name = opts.name, .run_in_ms = run_in_ms, .low_priority = opts.low_priority });
    }
    var queue = if (opts.low_priority) &self.low_priority else &self.high_priority;
    const seq = self._sequence + 1;
    self._sequence = seq;
    return queue.add(.{
        .ctx = ctx,
        .callback = cb,
        .sequence = seq,
        .name = opts.name,
        .finalizer = opts.finalizer,
        .run_at = milliTimestamp(.monotonic) + run_in_ms,
    });
}

pub fn run(self: *Scheduler) !void {
    try self.runQueue(&self.low_priority);
    try self.runQueue(&self.high_priority);
}

pub fn runFor(self: *Scheduler, budget_ms: u64) !void {
    if (budget_ms == 0) return;
    const start = milliTimestamp(.monotonic);

    if (self.run_high_first) {
        // A previous bounded pass exhausted its budget in low-priority work.
        // Repay the deferred high-priority queue once, then restore the normal
        // low-before-high event ordering.
        self.run_high_first = false;
        try self.runQueueUntil(&self.high_priority, start, budget_ms);
        if (milliTimestamp(.monotonic) - start >= budget_ms) return;
        return self.runQueueUntil(&self.low_priority, start, budget_ms);
    }

    try self.runQueueUntil(&self.low_priority, start, budget_ms);
    if (milliTimestamp(.monotonic) - start >= budget_ms) {
        // Repeating timers are requeued at low priority. Without carrying this
        // debt into the next pass, they can permanently starve ready high work.
        self.run_high_first = true;
        return;
    }
    try self.runQueueUntil(&self.high_priority, start, budget_ms);
}

pub fn hasReadyTasks(self: *Scheduler) bool {
    const now = milliTimestamp(.monotonic);
    return queueHasReadyTask(&self.low_priority, now) or queueHasReadyTask(&self.high_priority, now);
}

pub fn msToNextHigh(self: *Scheduler) ?u64 {
    const task = self.high_priority.peek() orelse return null;
    const now = milliTimestamp(.monotonic);
    if (task.run_at <= now) {
        return 0;
    }
    return @intCast(task.run_at - now);
}

fn runQueue(self: *Scheduler, queue: *Queue) !void {
    return self.runQueueUntil(queue, milliTimestamp(.monotonic), 500);
}

fn runQueueUntil(self: *Scheduler, queue: *Queue, start: u64, budget_ms: u64) !void {
    if (queue.count() == 0) {
        return;
    }
    var now = milliTimestamp(.monotonic);

    while (queue.peek()) |*task_| {
        if (task_.run_at > now) {
            return;
        }
        var task = queue.remove();
        if (comptime IS_DEBUG) {
            log.debug(.scheduler, "scheduler.runTask", .{ .name = task.name });
        }

        const repeat_in_ms = task.callback(task.ctx) catch |err| blk: {
            log.warn(.scheduler, "task.callback", .{ .name = task.name, .err = err });
            break :blk null;
        };

        if (repeat_in_ms) |ms| {
            // Task cannot be repeated immediately, and they should know that
            if (comptime IS_DEBUG) {
                std.debug.assert(ms != 0);
            }
            task.run_at = now + ms;
            try self.low_priority.add(task);
        }

        now = milliTimestamp(.monotonic);
        if (now - start >= budget_ms) {
            return;
        }
    }
    return;
}

fn queueHasReadyTask(queue: *Queue, now: u64) bool {
    const task = queue.peek() orelse return false;
    return task.run_at <= now;
}

fn finalizeTasks(queue: *Queue) void {
    var it = queue.iterator();
    while (it.next()) |t| {
        if (t.finalizer) |func| {
            func(t.ctx);
        }
    }
}

const Task = struct {
    run_at: u64,
    sequence: u64,
    ctx: *anyopaque,
    name: []const u8,
    callback: Callback,
    finalizer: ?Finalizer,
};

const Callback = *const fn (ctx: *anyopaque) anyerror!?u32;
const Finalizer = *const fn (ctx: *anyopaque) void;

const BudgetTestContext = struct {
    runs: *usize,
    busy_ms: u64,
    fail: bool = false,

    fn run(ctx: *anyopaque) anyerror!?u32 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.runs.* += 1;
        const end = milliTimestamp(.monotonic) + self.busy_ms;
        while (milliTimestamp(.monotonic) < end) {}
        if (self.fail) return error.BudgetTestFailure;
        return null;
    }
};

test "Scheduler: bounded run repays high-priority queue debt" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    defer scheduler.low_priority.deinit();
    defer scheduler.high_priority.deinit();

    var high_runs: usize = 0;
    var low_runs: usize = 0;
    var high_ctx = BudgetTestContext{ .runs = &high_runs, .busy_ms = 0 };
    var low_ctx = BudgetTestContext{ .runs = &low_runs, .busy_ms = 100, .fail = true };

    try scheduler.add(&low_ctx, BudgetTestContext.run, 0, .{ .low_priority = true });
    try scheduler.add(&low_ctx, BudgetTestContext.run, 0, .{ .low_priority = true });
    try scheduler.add(&high_ctx, BudgetTestContext.run, 0, .{});

    try scheduler.runFor(50);
    try std.testing.expectEqual(0, high_runs);
    try std.testing.expectEqual(1, low_runs);

    try scheduler.runFor(50);
    try std.testing.expectEqual(1, high_runs);
}
