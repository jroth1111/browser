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

const App = @import("../App.zig");
const CDP = @import("../cdp/CDP.zig");
const Notification = @import("../Notification.zig");

const js = @import("js/js.zig");
const Page = @import("Page.zig");
const Session = @import("Session.zig");
const Viewport = @import("Viewport.zig");
const HttpClient = @import("HttpClient.zig");
const PermissionState = @import("webapi/Permissions.zig").State;

const ArenaPool = App.ArenaPool;
const Allocator = std.mem.Allocator;
const log = lp.log;

// Browser is an instance of the browser.
// You can create multiple browser instances.
// A browser contains only one session.
const Browser = @This();

env: js.Env,
app: *App,
session: ?Session,
allocator: Allocator,
arena_pool: *ArenaPool,
http_client: HttpClient,
execution_watchdog: ExecutionWatchdog = .{},

// Permission state set via CDP Browser.grantPermissions / setPermission /
// resetPermissions, keyed by permission name (e.g. "geolocation"). Read back
// by navigator.permissions.query(). Scoped to the Browser so it persists
// across page navigations, mirroring how Chrome scopes permissions to the
// browser context. Keys are owned by `allocator`; values are enum tags.
permissions: std.StringHashMapUnmanaged(PermissionState) = .empty,

// Runtime viewport override set via Emulation.setDeviceMetricsOverride and
// cleared via clearDeviceMetricsOverride. Null means use the compile-time
// Viewport.default. Scoped to the Browser so it persists across page
// navigations (matching how Chrome scopes the override to the connection).
// Every viewport consumer reads it through Page.getViewport so they all
// observe the same (possibly overridden) value.
viewport_override: ?Viewport = null,

// used by sessions to allocate pages.
page_pool: std.heap.MemoryPool(Page),

// Pool for FinalizerCallback.Identity structs — the records V8 weak-callback
// parameters point at. Scoped to the Browser (i.e. the V8 Isolate's lifetime)
// rather than the Session: V8 can run a weak finalizer arbitrarily late, any
// time up until the Isolate is torn down, so these must outlive every Session.
// Freed in deinit *after* env.deinit() tears down the Isolate — the point past
// which no finalizer can fire.
fc_identity_pool: std.heap.MemoryPool(js.FinalizerCallback.Identity),

// Monotonic frame-ID generator scoped to this Browser (one per CDP
// connection). Lives here, not on Session, because CDP target IDs
// (encoded as `FID-{d:0>10}`) must be unique for the lifetime of the
// connection -- a Session-scoped counter would re-issue the same
// `FID-0000000001` for every fresh BrowserContext on the connection,
// which Playwright rejects with `Duplicate target FID-...` (issue
// #2472).
frame_id_gen: u32 = 0,

const ExecutionWatchdog = struct {
    const budget_ns = 5 * std.time.ns_per_s;
    const stack_size = 128 * 1024;

    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    thread: ?std.Thread = null,
    browser: ?*Browser = null,
    terminate_request: ?js.Env.ScopedTerminate = null,
    generation: u64 = 0,
    depth: usize = 0,
    armed: bool = false,
    stop: bool = false,
    fired: std.atomic.Value(bool) = .init(false),
    fire_count: std.atomic.Value(u64) = .init(0),

    fn start(self: *ExecutionWatchdog, browser: *Browser) !void {
        self.browser = browser;
        self.terminate_request = .{ .env = &browser.env };
        self.thread = try std.Thread.spawn(
            .{ .stack_size = stack_size },
            run,
            .{self},
        );
    }

    fn deinit(self: *ExecutionWatchdog) void {
        self.mutex.lock();
        self.stop = true;
        self.armed = false;
        self.generation +%= 1;
        self.condition.broadcast();
        self.mutex.unlock();
        if (self.thread) |thread| thread.join();
        self.thread = null;
        if (self.fired.swap(false, .acq_rel)) {
            self.terminate_request.?.cancel();
        }
    }

    fn arm(self: *ExecutionWatchdog) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.depth += 1;
        if (self.depth > 1) return;

        self.generation +%= 1;
        self.armed = true;
        self.fired.store(false, .release);
        self.condition.broadcast();
    }

    fn finish(self: *ExecutionWatchdog) bool {
        self.mutex.lock();
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
        if (self.depth > 0) {
            self.mutex.unlock();
            return false;
        }

        self.armed = false;
        self.generation +%= 1;
        self.condition.broadcast();
        const did_fire = self.fired.swap(false, .acq_rel);
        self.mutex.unlock();
        return did_fire;
    }

    fn hasFired(self: *const ExecutionWatchdog) bool {
        return self.fired.load(.acquire);
    }

    fn hasActiveScope(self: *ExecutionWatchdog) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.depth > 0;
    }

    fn run(self: *ExecutionWatchdog) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (!self.stop) {
            while (!self.stop and !self.armed) self.condition.wait(&self.mutex);
            if (self.stop) return;

            const generation = self.generation;
            var timer = std.time.Timer.start() catch unreachable;
            while (!self.stop and self.armed and self.generation == generation) {
                const elapsed = timer.read();
                if (elapsed >= budget_ns) {
                    self.fired.store(true, .release);
                    _ = self.fire_count.fetchAdd(1, .monotonic);
                    self.terminate_request.?.request();
                    self.armed = false;
                    break;
                }
                self.condition.timedWait(&self.mutex, budget_ns - elapsed) catch |err| switch (err) {
                    error.Timeout => {},
                };
            }
        }
    }
};

const InitOpts = struct {
    env: js.Env.InitOpts = .{},
};

// Allocate the next frame ID. Wrapping `+%` keeps this safe past 2^32
// allocations on a single connection (which would take days of
// continuous navigation; in practice we wrap the connection long
// before that). Callers must format with `FID-{d:0>10}` to match the
// existing CDP target-ID encoding (`src/cdp/id.zig`).
pub fn nextFrameId(self: *Browser) u32 {
    const id = self.frame_id_gen +% 1;
    self.frame_id_gen = id;
    return id;
}

pub fn init(self: *Browser, app: *App, opts: InitOpts, cdp: ?*CDP) !void {
    const allocator = app.allocator;

    var env = try js.Env.init(app, opts.env);
    errdefer env.deinit();

    self.* = .{
        .app = app,
        .env = env,
        .session = null,
        .allocator = allocator,
        .arena_pool = &app.arena_pool,
        .http_client = undefined,
        .page_pool = std.heap.MemoryPool(Page).init(allocator),
        .fc_identity_pool = .init(allocator),
    };
    try self.http_client.init(allocator, &app.network, cdp);
    errdefer self.http_client.deinit();
    try self.execution_watchdog.start(self);
}

pub fn deinit(self: *Browser) void {
    self.execution_watchdog.deinit();
    self.closeSession();
    self.env.deinit();
    // After env.deinit() the Isolate is gone, so no further weak finalizer can
    // fire — only now is it safe to free the pool backing their parameters.
    self.fc_identity_pool.deinit();
    self.page_pool.deinit();
    self.http_client.deinit();
    self.clearPermissions();
    self.permissions.deinit(self.allocator);
}

// Set (or overwrite) the stored state for a permission. The name is duped into
// `allocator`; the state is a plain enum tag. Used by CDP
// Browser.grantPermissions / setPermission.
pub fn setPermission(self: *Browser, name: []const u8, state: PermissionState) !void {
    const gop = try self.permissions.getOrPut(self.allocator, name);
    if (!gop.found_existing) {
        gop.key_ptr.* = self.allocator.dupe(u8, name) catch |err| {
            _ = self.permissions.remove(name);
            return err;
        };
    }
    gop.value_ptr.* = state;
}

// Clear all stored permissions, freeing the keys. Used by CDP
// Browser.resetPermissions and on teardown.
pub fn clearPermissions(self: *Browser) void {
    var it = self.permissions.keyIterator();
    while (it.next()) |key| {
        self.allocator.free(key.*);
    }
    self.permissions.clearRetainingCapacity();
}

// The viewport every consumer should read: the runtime override if set,
// otherwise the compile-time default.
pub fn getViewport(self: *const Browser) Viewport {
    return self.viewport_override orelse Viewport.default;
}

pub fn newSession(self: *Browser, notification: *Notification) !*Session {
    self.closeSession();
    self.session = @as(Session, undefined);
    errdefer self.session = null;
    const session = &self.session.?;
    try Session.init(session, self, notification);
    return session;
}

pub fn closeSession(self: *Browser) void {
    if (self.session) |*session| {
        session.deinit();
        self.session = null;
    }
}

pub fn runMicrotasks(self: *Browser) void {
    self.env.runMicrotasks();
}

pub fn runMacrotasks(self: *Browser) !void {
    const env = &self.env;

    self.armExecutionWatchdog();
    defer self.finishExecutionWatchdog();

    try self.env.runMacrotasks();
    if (self.execution_watchdog.hasFired()) return;
    env.pumpMessageLoop();
    if (self.execution_watchdog.hasFired()) return;

    // either of the above could have queued more microtasks
    env.runMicrotasks();
}

pub fn armExecutionWatchdog(self: *Browser) void {
    if (!self.execution_watchdog.hasActiveScope()) {
        self.env.discardTerminatedMicrotasks();
    }
    self.execution_watchdog.arm();
}

pub fn finishExecutionWatchdog(self: *Browser) void {
    if (self.execution_watchdog.finish()) {
        self.env.markTerminatedMicrotasks();
        self.env.discardTerminatedMicrotasks();
        self.execution_watchdog.terminate_request.?.cancel();
        log.warn(.js, "page execution watchdog", .{ .budget_ms = ExecutionWatchdog.budget_ns / std.time.ns_per_ms });
    }
}

pub fn executionWatchdogFireCount(self: *const Browser) u64 {
    return self.execution_watchdog.fire_count.load(.monotonic);
}

pub fn hasBackgroundTasks(self: *Browser) bool {
    return self.env.hasBackgroundTasks();
}

pub fn waitForBackgroundTasks(self: *Browser) void {
    self.armExecutionWatchdog();
    defer self.finishExecutionWatchdog();
    self.env.waitForBackgroundTasks(&self.execution_watchdog.fired);
}

pub fn msToNextMacrotask(self: *Browser) ?u64 {
    return self.env.msToNextMacrotask();
}

pub fn msTo(self: *Browser) bool {
    return self.env.hasBackgroundTasks();
}

pub fn runIdleTasks(self: *const Browser) void {
    self.env.runIdleTasks();
}
