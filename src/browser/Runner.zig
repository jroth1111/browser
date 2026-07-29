// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
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

const js = @import("js/js.zig");
const Frame = @import("Frame.zig");
const Browser = @import("Browser.zig");
const Session = @import("Session.zig");
const HttpClient = @import("HttpClient.zig");

const Node = @import("webapi/Node.zig");
const Selector = @import("webapi/selector/Selector.zig");

const log = lp.log;
const IS_DEBUG = builtin.mode == .Debug;

const Runner = @This();

session: *Session,
browser: *Browser,
http_client: *HttpClient,

pub const Opts = struct {};

pub fn init(session: *Session, _: Opts) Runner {
    return .{
        .session = session,
        .browser = session.browser,
        .http_client = &session.browser.http_client,
    };
}

pub const WaitCondition = struct {
    frame_id: u32,
    until: lp.Config.WaitUntil = .done,
    status: Status = .pending,

    const Status = union(enum) {
        pending,
        complete,
        err: anyerror,
    };
};

const WaitForFrameOpts = struct {
    until: lp.Config.WaitUntil = .done,
};
pub fn waitForFrame(self: *Runner, frame_id: u32, timeout_ms: u32, opts: WaitForFrameOpts) !void {
    const condition = WaitCondition{ .frame_id = frame_id, .until = opts.until };
    var conditions = [_]WaitCondition{condition};
    _ = try self._wait(false, timeout_ms, &conditions);
    try firstConditionError(&conditions);
}

pub fn waitForFrameCDP(self: *Runner, frame_id: u32, timeout_ms: u32, until: lp.Config.WaitUntil) !void {
    const condition = WaitCondition{ .frame_id = frame_id, .until = until };
    var conditions = [_]WaitCondition{condition};
    // Unlike waitForFrame, we deliberately don't surface a per-frame error here.
    // The frame we're waiting on can legitimately disappear mid-wait.
    _ = try self._wait(true, timeout_ms, &conditions);
}

// Helper to wait for all currently loaded frames
pub fn waitForAll(self: *Runner, timeout_ms: u32, opts: WaitForFrameOpts) !void {
    const session = self.session;
    const arena = try session.getArena(.tiny, "Runner.waitForAll");
    defer session.releaseArena(arena);

    var pages_to_wait: usize = 0;
    for (session.pages.items) |page| {
        if (page.replacement == null) {
            pages_to_wait += 1;
        }
    }

    const conditions = try arena.alloc(WaitCondition, pages_to_wait);
    var i: usize = 0;
    for (session.pages.items) |page| {
        if (page.replacement == null) {
            conditions[i] = .{ .frame_id = page.frame._frame_id, .until = opts.until };
            i += 1;
        }
    }
    _ = try self._wait(false, timeout_ms, conditions);
    try firstConditionError(conditions);
}

pub fn wait(self: *Runner, timeout_ms: u32, conditions: []WaitCondition) !void {
    try self._wait(false, timeout_ms, conditions);
}

pub const WaitResult = enum { completed, timeout };
pub fn waitResult(self: *Runner, timeout_ms: u32, conditions: []WaitCondition) !WaitResult {
    return self._wait(false, timeout_ms, conditions);
}

// Wait until either a parse-state / load goal is reached or `opts.ms`
// elapses. Returns as soon as _tick reports .done.
fn _wait(self: *Runner, comptime is_cdp: bool, timeout_ms: u32, conditions: []WaitCondition) !WaitResult {
    const browser = self.browser;

    var timer = try std.time.Timer.start();

    // Periodic V8 GC hint during long waits. V8 is otherwise only nudged on
    // session/page teardown (Browser.zig, Page.zig), so a page that stays
    // alive for seconds while running heavy JS accumulates wrappers and
    // external-ref'd Zig allocations V8 has no reason to drop. `.moderate`
    // speeds up incremental GC without stalling the tick.
    const gc_hint_period_ns: u64 = std.time.ns_per_s;
    var gc_hint_timer = std.time.Timer.start() catch unreachable;

    while (true) {
        // The CDP path can have its session closed mid-wait: a command
        // dispatched by the previous tick (e.g. disposeBrowserContext) can call
        // browser.closeSession (see the `browser` field comment). So re-derive
        // the live session each pass there and end the wait once it's gone.
        // Non-CDP callers hold a stable session, so they skip the check.
        const session = if (comptime is_cdp)
            (if (browser.session) |*s| s else return .completed)
        else
            self.session;

        // Cooperative cancellation. Set by the agent so SIGINT can break
        // out of a long wait without the user sitting through the timeout.
        if (session.isCancelled()) {
            return error.Cancelled;
        }

        if (gc_hint_timer.read() >= gc_hint_period_ns) {
            gc_hint_timer.reset();
            browser.env.memoryPressureNotification(.moderate);
        }
        session.processDestroyQueues();

        const tick_result = self._tick(is_cdp, 200, conditions) catch |err| {
            switch (err) {
                error.JsError => {}, // already logged (with hopefully more context)
                error.ClientDisconnected => {}, // CDP layer already logged this
                else => log.err(.browser, "session wait", .{ .err = err }),
            }
            return err;
        };

        const next_ms = switch (tick_result) {
            .ok => |next_ms| next_ms,
            .done => done_blk: {
                if (comptime is_cdp == false) {
                    return .completed;
                }

                // is_cdp keeps the loop alive past .done so the worker
                // can observe CDP commands. We have nothing useful to do here
                // but we can ask the http_client to wait for CDP messages.
                const elapsed: u32 = @intCast(timer.read() / std.time.ns_per_ms);
                if (elapsed >= timeout_ms) {
                    return .timeout;
                }
                try self.http_client.tick(@min(timeout_ms - elapsed, 200), .all);
                break :done_blk 0;
            },
        };

        const ms_elapsed: u32 = @intCast(timer.read() / std.time.ns_per_ms);
        if (ms_elapsed >= timeout_ms) {
            return .timeout;
        }
        if (next_ms > 0) {
            std.Thread.sleep(std.time.ns_per_ms * next_ms);
        }
    }
}

pub const TickResult = union(enum) {
    done,
    ok: u32,
};
pub fn tickForFrame(self: *Runner, frame_id: u32, timeout_ms: u32, opts: WaitForFrameOpts) !TickResult {
    const condition = WaitCondition{ .frame_id = frame_id, .until = opts.until };
    var conditions = [_]WaitCondition{condition};
    const result = try self.tick(timeout_ms, &conditions);
    try firstConditionError(&conditions);
    return result;
}
pub fn tick(self: *Runner, timeout_ms: u32, conditions: []WaitCondition) !TickResult {
    return self._tick(false, timeout_ms, conditions);
}

fn tickIsDone(ms_to_next_macrotask: ?u64, network_idle: bool, foreground_pending: bool) bool {
    return ms_to_next_macrotask == null and network_idle and !foreground_pending;
}

fn canWaitForBackgroundTasks(is_cdp: bool, network_idle: bool, foreground_pending: bool) bool {
    return !is_cdp and network_idle and !foreground_pending;
}

fn _tick(self: *Runner, comptime is_cdp: bool, timeout_ms: u32, conditions: []WaitCondition) !TickResult {
    const session = self.session;
    const browser = self.browser;
    const http_client = self.http_client;

    // Drain queued navigations across every live page (one page per call).
    // JavaScript URLs execute synchronously here, before the macrotask safe
    // point below, so they need the same execution deadline.
    const processed_navigation = blk: {
        browser.armExecutionWatchdog();
        defer browser.finishExecutionWatchdog();
        break :blk try session.processQueuedNavigation();
    };
    // A navigation can swap a frame pointer or the page set,
    // so restart the tick to re-resolve cleanly.
    if (processed_navigation) {
        return .{ .ok = 0 };
    }

    const foreground_pending = if (hasRunnablePage(session))
        try browser.runMacrotasks()
    else
        false;

    const http_active = http_client.http_active;
    const http_next_tick = http_client.next_tick_count;
    const total_http_activity = http_active + http_next_tick + http_client.interception_layer.intercepted;
    const total_network_activity = total_http_activity + http_client.ws_active;

    const ms_to_next_macrotask = browser.msToNextMacrotask();
    const network_idle = total_network_activity == 0 and http_client.queue.first == null and http_client.ready_queue.first == null;
    const is_done = tickIsDone(ms_to_next_macrotask, network_idle, foreground_pending);

    // _we_ have nothing to run, but v8 is working on background tasks. We'll
    // wait for them. Don't do this for CDP, since new CDP messages can always
    // come in at any time.
    if (canWaitForBackgroundTasks(is_cdp, network_idle, foreground_pending) and browser.hasBackgroundTasks()) {
        browser.waitForBackgroundTasks();
        return .{ .ok = 0 };
    }

    var want_http_tick = false;

    for (conditions) |*condition| {
        if (condition.status != .pending) {
            // this condition is at a terminal state
            continue;
        }

        const page = session.pendingOrLivePage(condition.frame_id) orelse {
            condition.status = .{ .err = error.FrameNotFound };
            continue;
        };

        const frame = &page.frame;
        switch (frame._parse_state) {
            .err => |err| {
                frame._parse_state = .{ .raw_done = @errorName(err) };
                condition.status = .{ .err = err };
            },
            .raw_done => {
                condition.status = .complete;
            },
            .pre, .raw, .text, .image, .download => {
                if (total_network_activity == 0) {
                    condition.status = .complete;
                } else {
                    want_http_tick = true;
                }
            },
            .html, .complete => {
                if (frame._notified_network_almost_idle.check(total_http_activity <= 2)) {
                    frame.notifyNetworkAlmostIdle();
                }
                if (frame._notified_network_idle.check(total_http_activity == 0)) {
                    frame.notifyNetworkIdle();
                }

                const met = switch (condition.until) {
                    .done => is_done,
                    .domcontentloaded => frame._load_state == .load or frame._load_state == .complete,
                    .load => frame._load_state == .complete,
                    .networkidle => frame._notified_network_idle == .done,
                    .networkalmostidle => frame._notified_network_almost_idle == .done,
                };

                // `met` resolves the condition. Otherwise, as long as there's
                // still work in flight (network or pending macrotasks), keep
                // ticking. `is_done` means the page went fully idle without
                // reaching the goal — there's nothing left to wait on, so
                // resolve rather than spin forever.
                if (met or is_done) {
                    condition.status = .complete;
                } else {
                    want_http_tick = true;
                }
            },
        }
    }

    if ((comptime is_cdp) or want_http_tick or foreground_pending) {
        // Keep socket polling well below the execution deadline so the
        // watchdog measures callback/JavaScript work, not an idle wait.
        var ms_to_wait = @min(@min(timeout_ms, ms_to_next_macrotask orelse 200), 200);
        if (foreground_pending) {
            // The cooperative V8 pump hit a cap. Drain CDP/network without
            // blocking, then immediately give the finite remainder another turn.
            ms_to_wait = 0;
        } else if (browser.hasBackgroundTasks()) {
            // background work will queue more to do soon — don't block long
            // for a client message; loop back and run macrotasks instead.
            ms_to_wait = @min(ms_to_wait, 10);
        }
        browser.armExecutionWatchdog();
        defer browser.finishExecutionWatchdog();
        try http_client.tick(@intCast(ms_to_wait), .all);
        return .{ .ok = 0 };
    }

    return .done;
}

pub fn waitForSelector(self: *Runner, frame_id: u32, selector: [:0]const u8, timeout_ms: u32) !*Node.Element {
    const session = self.session;
    const arena = try session.getArena(.small, "Runner.waitForSelector");
    defer session.releaseArena(arena);

    var timer = try std.time.Timer.start();
    const parsed_selector = try Selector.parseLeaky(arena, selector);

    while (true) {
        if (session.isCancelled()) {
            return error.Cancelled;
        }

        const page = session.pendingOrLivePage(frame_id) orelse {
            return error.FrameNotFound;
        };
        const frame = &page.frame;

        if (try parsed_selector.query(frame.document.asNode(), frame)) |el| {
            return el;
        }

        const elapsed: u32 = @intCast(timer.read() / std.time.ns_per_ms);
        if (elapsed >= timeout_ms) {
            return error.Timeout;
        }
        switch (try self.tickForFrame(frame_id, timeout_ms - elapsed, .{ .until = .done })) {
            // Idle: poll so `timeout_ms` means "wait up to N ms", not "fail now".
            .done => std.Thread.sleep(std.time.ns_per_ms * @as(u64, @min(timeout_ms - elapsed, 50))),
            .ok => |recommended_sleep_ms| {
                if (recommended_sleep_ms > 0) {
                    std.Thread.sleep(std.time.ns_per_ms * recommended_sleep_ms);
                }
            },
        }
    }
}

pub fn waitForScript(self: *Runner, frame_id: u32, src: [:0]const u8, timeout_ms: u32) !void {
    const session = self.session;
    var timer = try std.time.Timer.start();

    // Compile the script once and re-use the compiled form. A tick can create a
    // new context (an internal navigation), so we keep an unbound script (one
    // not bound to a particular context) and bind it to the current context on
    // each tick. Compilation is context-independent, so we can do it up front
    // in whatever context the frame currently has.
    var compiled: js.Script.Unbound.Global = blk: {
        const page = session.pendingOrLivePage(frame_id) orelse {
            return error.FrameNotFound;
        };
        const frame = &page.frame;

        var ls: js.Local.Scope = undefined;
        frame.js.localScope(&ls);
        defer ls.deinit();

        var try_catch: js.TryCatch = undefined;
        try_catch.init(&ls.local);
        defer try_catch.deinit();

        const s = ls.local.compile(src, "wait_script") catch |err| {
            const caught = try_catch.caughtOrError(frame.call_arena, err);
            log.err(.app, "wait script error", .{ .err = caught });
            return error.ScriptError;
        };
        break :blk s.getUnboundScript().persist(ls.local.isolate);
    };
    defer compiled.deinit();

    while (true) {
        if (session.isCancelled()) {
            return error.Cancelled;
        }

        const page = session.pendingOrLivePage(frame_id) orelse {
            return error.FrameNotFound;
        };
        const frame = &page.frame;

        var ls: js.Local.Scope = undefined;
        frame.js.localScope(&ls);
        defer ls.deinit();

        var try_catch: js.TryCatch = undefined;
        try_catch.init(&ls.local);
        defer try_catch.deinit();

        const script = compiled.get(ls.local.isolate).bindToCurrentContext(&ls.local);
        const value = script.run() catch |err| {
            const caught = try_catch.caughtOrError(frame.call_arena, err);
            log.err(.app, "wait script error", .{ .err = caught });
            return error.ScriptError;
        };

        if (value.toBool()) {
            return;
        }

        const elapsed: u32 = @intCast(timer.read() / std.time.ns_per_ms);
        if (elapsed >= timeout_ms) {
            return error.Timeout;
        }
        switch (try self.tickForFrame(frame_id, timeout_ms - elapsed, .{ .until = .done })) {
            // Idle: poll so `timeout_ms` means "wait up to N ms", not "fail now".
            .done => std.Thread.sleep(std.time.ns_per_ms * @as(u64, @min(timeout_ms - elapsed, 50))),
            .ok => |recommended_sleep_ms| {
                if (recommended_sleep_ms > 0) {
                    std.Thread.sleep(std.time.ns_per_ms * recommended_sleep_ms);
                }
            },
        }
    }
}

fn firstConditionError(conditions: []const WaitCondition) !void {
    for (conditions) |condition| {
        switch (condition.status) {
            .err => |err| return err,
            else => {},
        }
    }
}

fn hasRunnablePage(session: *Session) bool {
    for (session.pages.items) |page| {
        switch (page.frame._parse_state) {
            .html, .complete => return true,
            else => {},
        }
    }
    return false;
}

const testing = @import("../testing.zig");
test "Runner: waitForSelector timeout" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();

    var runner = page.session.runner(.{});
    try testing.expectError(error.Timeout, runner.waitForSelector(page.frame_id, "#nope", 10));
}

test "Runner: waitForSelector" {
    defer testing.reset();
    const page = try testing.pageTest("runner/runner1.html", .{});

    var runner = page.session.runner(.{});
    const el = try runner.waitForSelector(page.frame_id, "#sel1", 10);
    try testing.expectEqual("selector-1-content", try el.asNode().getTextContentAlloc(testing.arena_allocator));
}

test "Runner: foreground work prevents premature completion" {
    try testing.expect(tickIsDone(null, true, false));
    try testing.expect(!tickIsDone(null, true, true));
    try testing.expect(!tickIsDone(0, true, false));
    try testing.expect(!tickIsDone(null, false, false));
}

test "Runner: foreground work takes priority over background wait" {
    try testing.expect(canWaitForBackgroundTasks(false, true, false));
    try testing.expect(!canWaitForBackgroundTasks(false, true, true));
    try testing.expect(!canWaitForBackgroundTasks(true, true, false));
    try testing.expect(!canWaitForBackgroundTasks(false, false, false));
}

test "Runner: iframe macrotasks yield between contexts" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;

    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();

    var create_timer = try std.time.Timer.start();
    const created = try ls.local.compileAndRun(
        \\window.__busyDone = 0;
        \\for (let i = 0; i < 8; i++) {
        \\  const frame = document.createElement('iframe');
        \\  frame.src = 'javascript:void setTimeout(() => {' +
        \\    'const end = Date.now() + 100;' +
        \\    'while (Date.now() < end) {}' +
        \\    'parent.__busyDone++;' +
        \\  '}, 0)';
        \\  document.body.appendChild(frame);
        \\}
        \\document.querySelectorAll('iframe').length;
    , null);
    try testing.expectEqual(8.0, try created.toF64());
    try testing.expect(create_timer.read() < 2 * std.time.ns_per_s);

    var pass_timer = try std.time.Timer.start();
    _ = try page.session.browser.runMacrotasks();
    try testing.expect(pass_timer.read() < 500 * std.time.ns_per_ms);
    try testing.expectEqual(1.0, try (try ls.local.compileAndRun("window.__busyDone", null)).toF64());

    for (0..7) |_| {
        _ = try page.session.browser.runMacrotasks();
    }
    try testing.expectEqual(8.0, try (try ls.local.compileAndRun("window.__busyDone", null)).toF64());
}

test "Runner: new iframe context waits for next macrotask pass" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;

    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();

    const created = try ls.local.compileAndRun(
        \\window.__existingDone = 0;
        \\window.__newDone = 0;
        \\for (let i = 0; i < 3; i++) {
        \\  const frame = document.createElement('iframe');
        \\  frame.src = 'javascript:void setTimeout(() => {' +
        \\    'parent.__existingDone++;' +
        \\    (i === 0 ?
        \\      "const child=document.createElement('iframe');" +
        \\      "child.src='javascript:void setTimeout(() => parent.__newDone++, 0)';" +
        \\      'parent.document.body.appendChild(child);' : '') +
        \\  '}, 0)';
        \\  document.body.appendChild(frame);
        \\}
        \\document.querySelectorAll('iframe').length;
    , null);
    try testing.expectEqual(3.0, try created.toF64());

    // Start from a nonzero cursor so a live-array walk would reach the appended
    // context before wrapping to every context that existed at pass start.
    page.session.browser.env.macrotask_context_cursor = 1;
    _ = try page.session.browser.runMacrotasks();
    try testing.expectEqual(3.0, try (try ls.local.compileAndRun("window.__existingDone", null)).toF64());
    try testing.expectEqual(0.0, try (try ls.local.compileAndRun("window.__newDone", null)).toF64());

    _ = try page.session.browser.runMacrotasks();
    try testing.expectEqual(1.0, try (try ls.local.compileAndRun("window.__newDone", null)).toF64());
}

test "Runner: macrotask budget stops between callbacks" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;

    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();

    _ = try ls.local.compileAndRun(
        \\window.__busyDone = 0;
        \\const frame = document.createElement('iframe');
        \\frame.src = 'javascript:void (() => {' +
        \\  'for (let i = 0; i < 8; i++) {' +
        \\    'setTimeout(() => {' +
        \\      'const end = Date.now() + 100;' +
        \\      'while (Date.now() < end) {}' +
        \\      'parent.__busyDone++;' +
        \\    '}, 0);' +
        \\  '}' +
        \\'})()';
        \\document.body.appendChild(frame);
    , null);

    var pass_timer = try std.time.Timer.start();
    _ = try page.session.browser.runMacrotasks();
    try testing.expect(pass_timer.read() < 500 * std.time.ns_per_ms);
    try testing.expectEqual(1.0, try (try ls.local.compileAndRun("window.__busyDone", null)).toF64());

    for (0..7) |_| {
        _ = try page.session.browser.runMacrotasks();
    }
    try testing.expectEqual(8.0, try (try ls.local.compileAndRun("window.__busyDone", null)).toF64());
}

test "Runner: execution watchdog interrupts self-replenishing microtasks" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;

    {
        var ls: js.Local.Scope = undefined;
        frame.js.localScope(&ls);
        defer ls.deinit();

        _ = try ls.local.compileAndRun(
            \\setTimeout(() => {
            \\  const spin = () => {
            \\    const end = Date.now() + 5;
            \\    while (Date.now() < end) {}
            \\    Promise.resolve().then(spin);
            \\  };
            \\  Promise.resolve().then(spin);
            \\}, 0);
        , null);
    }

    const fires_before = page.session.browser.executionWatchdogFireCount();
    var pass_timer = try std.time.Timer.start();
    _ = try page.session.browser.runMacrotasks();
    try testing.expect(pass_timer.read() < 8 * std.time.ns_per_s);
    try testing.expectEqual(fires_before + 1, page.session.browser.executionWatchdogFireCount());
    try testing.expect(!page.session.browser.env.terminatePending());

    // The next worker pass must not re-enter the interrupted Promise chain.
    _ = try page.session.browser.runMacrotasks();
    try testing.expectEqual(fires_before + 1, page.session.browser.executionWatchdogFireCount());

    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();
    try testing.expectEqual(42.0, try (try ls.local.compileAndRun("21 * 2", null)).toF64());
}

test "Runner: execution watchdog discards promises queued before synchronous termination" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;

    page.session.browser.armExecutionWatchdog();
    {
        var ls: js.Local.Scope = undefined;
        frame.js.localScope(&ls);
        defer ls.deinit();

        _ = ls.local.compileAndRun(
            \\globalThis.__queuedBeforeTermination = false;
            \\Promise.resolve().then(() => {
            \\  globalThis.__queuedBeforeTermination = true;
            \\});
            \\while (true) {}
        , null) catch {};
    }
    page.session.browser.finishExecutionWatchdog();

    _ = try page.session.browser.runMacrotasks();
    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();
    try testing.expect(!(try ls.local.compileAndRun(
        "globalThis.__queuedBeforeTermination",
        null,
    )).toBool());
}

test "Runner: execution watchdog defers queue reset while a context is entered" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;
    const env = &page.session.browser.env;

    env.markTerminatedMicrotasks();
    {
        var ls: js.Local.Scope = undefined;
        frame.js.localScope(&ls);
        defer ls.deinit();

        env.discardTerminatedMicrotasks();
        try testing.expect(env.discard_all_microtasks_pending);
    }

    env.discardTerminatedMicrotasks();
    try testing.expect(!env.discard_all_microtasks_pending);
}

test "Runner: execution watchdog interrupts JavaScript URL navigation" {
    const fires_before = testing.test_browser.executionWatchdogFireCount();
    var pass_timer = try std.time.Timer.start();
    const page = try testing.pageTest("runner/runaway-javascript-url.html", .{});
    defer page.close();
    try testing.expect(pass_timer.read() < 8 * std.time.ns_per_s);
    try testing.expectEqual(fires_before + 1, page.session.browser.executionWatchdogFireCount());

    const frame = page.frame().?;
    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();
    try testing.expectEqual(42.0, try (try ls.local.compileAndRun("21 * 2", null)).toF64());
}

test "Runner: execution watchdog permits finite microtasks" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;

    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();

    _ = try ls.local.compileAndRun(
        \\window.__finiteCount = 0;
        \\setTimeout(() => {
        \\  const step = () => {
        \\    window.__finiteCount += 1;
        \\    if (window.__finiteCount < 100) {
        \\      Promise.resolve().then(step);
        \\    }
        \\  };
        \\  Promise.resolve().then(step);
        \\}, 0);
    , null);

    const fires_before = page.session.browser.executionWatchdogFireCount();
    _ = try page.session.browser.runMacrotasks();
    try testing.expectEqual(fires_before, page.session.browser.executionWatchdogFireCount());
    try testing.expectEqual(100.0, try (try ls.local.compileAndRun("window.__finiteCount", null)).toF64());
}

test "Runner: execution watchdog permits long finite callback" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();
    const frame = page.frame().?;

    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();

    _ = try ls.local.compileAndRun(
        \\window.__longFiniteDone = false;
        \\setTimeout(() => {
        \\  const end = Date.now() + 1200;
        \\  while (Date.now() < end) {}
        \\  window.__longFiniteDone = true;
        \\}, 0);
    , null);

    const fires_before = page.session.browser.executionWatchdogFireCount();
    _ = try page.session.browser.runMacrotasks();
    try testing.expectEqual(fires_before, page.session.browser.executionWatchdogFireCount());
    try testing.expect((try ls.local.compileAndRun("window.__longFiniteDone", null)).toBool());
}

test "Runner: waitForScript timeout" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();

    var runner = page.session.runner(.{});
    try testing.expectError(error.Timeout, runner.waitForScript(page.frame_id, "document.querySelector('#nope')", 10));
}

test "Runner: waitForScript" {
    const page = try testing.pageTest("runner/runner1.html", .{});
    defer page.close();

    var runner = page.session.runner(.{});
    try runner.waitForScript(page.frame_id, "document.querySelector('#sel1')", 10);
}
