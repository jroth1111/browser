// Copyright (C) 2023-2024  Lightpanda (Selecy SAS)
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
const builtin = @import("builtin");

const js = @import("../../browser/js/js.zig");
const CDP = @import("../CDP.zig");
const Notification = @import("../../Notification.zig");

const Allocator = std.mem.Allocator;

pub fn processMessage(cmd: *CDP.Command) !void {
    const action = std.meta.stringToEnum(enum {
        enable,
        disable,
        runIfWaitingForDebugger,
        evaluate,
        addBinding,
        callFunctionOn,
        releaseObject,
        getProperties,
    }, cmd.input.action) orelse return error.UnknownMethod;

    switch (action) {
        .runIfWaitingForDebugger => return cmd.sendResult(null, .{}),
        .enable => return enable(cmd),
        .disable => return disable(cmd),
        else => return sendInspector(cmd, action),
    }
}

fn enable(cmd: *CDP.Command) !void {
    const bc = cmd.browser_context orelse return error.BrowserContextNotLoaded;
    try bc.runtimeEnable();
    return sendInspector(cmd, .enable);
}

fn disable(cmd: *CDP.Command) !void {
    const bc = cmd.browser_context orelse return error.BrowserContextNotLoaded;
    bc.runtimeDisable();
    return sendInspector(cmd, .disable);
}

fn sendInspector(cmd: *CDP.Command, action: anytype) !void {
    // save script in file at debug mode
    if (builtin.mode == .Debug) {
        try logInspector(cmd, action);
    }

    const bc = cmd.browser_context orelse return error.BrowserContextNotLoaded;
    const id = cmd.input.id orelse return error.RequiredId;

    const checkpoint: CDP.BrowserContext.InspectorCheckpoint = if (action == .evaluate) blk: {
        const params = try cmd.params(struct {
            contextId: ?i32 = null,
        });
        const context_id = if (params) |p| p.contextId else null;
        break :blk if (bc.executionContext(context_id)) |ctx|
            .{ .context = ctx }
        else
            .none;
    } else .all;

    // Hold the native result until the selected queue finishes checkpointing.
    // If that checkpoint trips the watchdog, discard the otherwise-successful
    // native response and return one same-id termination error instead. A command
    // with no immediate result and no watchdog fire remains legitimately pending
    // (for example Runtime.evaluate with awaitPromise).
    switch (bc.callInspector(cmd.input.json, id, checkpoint)) {
        .completed, .pending => {},
        .terminated => return cmd.sendError(-32000, "Execution was terminated", .{}),
    }
}

fn logInspector(cmd: *CDP.Command, action: anytype) !void {
    const script = switch (action) {
        .evaluate => blk: {
            const params = (try cmd.params(struct {
                expression: []const u8,
                // contextId: ?u8 = null,
                // returnByValue: ?bool = null,
                // awaitPromise: ?bool = null,
                // userGesture: ?bool = null,
            })) orelse return error.InvalidParams;

            break :blk params.expression;
        },
        .callFunctionOn => blk: {
            const params = (try cmd.params(struct {
                functionDeclaration: []const u8,
                // objectId: ?[]const u8 = null,
                // executionContextId: ?u8 = null,
                // arguments: ?[]struct {
                //     value: ?[]const u8 = null,
                //     objectId: ?[]const u8 = null,
                // } = null,
                // returnByValue: ?bool = null,
                // awaitPromise: ?bool = null,
                // userGesture: ?bool = null,
            })) orelse return error.InvalidParams;

            break :blk params.functionDeclaration;
        },
        else => return,
    };
    const id = cmd.input.id orelse return error.RequiredId;
    const name = try std.fmt.allocPrint(cmd.arena, "id_{d}.js", .{id});

    var dir = try std.fs.cwd().makeOpenPath(".zig-cache/tmp", .{});
    defer dir.close();

    const f = try dir.createFile(name, .{});
    defer f.close();
    try f.writeAll(script);
}

const RemoteObject = struct {
    type: []const u8,
    subtype: ?[]const u8,
    className: ?[]const u8,
    description: ?[]const u8,
    objectId: ?[]const u8,
    value: js.Value,
};

const ConsoleMessage = struct {
    type: []const u8,
    executionContextId: i32,
    timestamp: u64,
    args: []RemoteObject,
};

pub fn consoleMessage(arena: Allocator, bc: *CDP.BrowserContext, event: *const Notification.ConsoleMessage) !void {
    const session_id = bc.session_id orelse return;
    const frame = bc.mainFrame() orelse return error.FrameNotLoaded;

    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();

    const context_id = bc.inspector_session.inspector.getContextId(&ls.local);

    var args: std.ArrayList(RemoteObject) = .empty;
    for (event.values) |value| {
        const remote_object = try bc.inspector_session.getRemoteObject(
            &ls.local,
            "",
            value,
        );
        defer remote_object.deinit();

        try args.append(arena, .{
            .type = try remote_object.getType(arena),
            .subtype = try remote_object.getSubtype(arena),
            .className = try remote_object.getClassName(arena),
            .description = try remote_object.getDescription(arena),
            .objectId = try remote_object.getObjectId(arena),
            .value = value,
        });
    }

    return bc.cdp.sendEvent("Runtime.consoleAPICalled", ConsoleMessage{
        .type = @tagName(event.type),
        .timestamp = event.timestamp,
        .executionContextId = context_id,
        .args = args.items,
    }, .{ .session_id = session_id });
}

const testing = @import("../testing.zig");

test "cdp.runtime: evaluate checkpoints only its selected execution context" {
    var ctx = try testing.context();
    defer ctx.deinit();

    const bc = try ctx.loadBrowserContext(.{ .id = "BID-EVAL", .url = "hi.html", .target_id = "FID-0000000EVA".* });
    const frame = bc.mainFrame() orelse unreachable;
    const world = try bc.createIsolatedWorld("runtime-test", true);
    const isolated = try world.createContext(frame);

    var isolated_scope: js.Local.Scope = undefined;
    isolated.localScope(&isolated_scope);
    defer isolated_scope.deinit();
    bc.inspector_session.inspector.contextCreated(
        &isolated_scope.local,
        "runtime-test",
        frame.origin orelse "",
        "{\"isDefault\":false,\"type\":\"isolated\",\"frameId\":\"FID-0000000EVA\"}",
        false,
    );
    const isolated_id = bc.inspector_session.inspector.getContextId(&isolated_scope.local);

    var main_scope: js.Local.Scope = undefined;
    frame.js.localScope(&main_scope);
    defer main_scope.deinit();
    const main_id = bc.inspector_session.inspector.getContextId(&main_scope.local);

    // Bypass BrowserContext.callInspector so both queues remain pending until a
    // Runtime.evaluate command chooses which one to checkpoint.
    const queue_main = try std.fmt.allocPrint(
        testing.allocator,
        "{{\"id\":901,\"method\":\"Runtime.evaluate\",\"params\":{{\"contextId\":{d},\"expression\":\"globalThis.__mainDone=false;queueMicrotask(()=>globalThis.__mainDone=true)\"}}}}",
        .{main_id},
    );
    defer testing.allocator.free(queue_main);
    bc.inspector_session.send(queue_main);
    const queue_isolated = try std.fmt.allocPrint(
        testing.allocator,
        "{{\"id\":902,\"method\":\"Runtime.evaluate\",\"params\":{{\"contextId\":{d},\"expression\":\"globalThis.__isolatedDone=false;queueMicrotask(()=>globalThis.__isolatedDone=true)\"}}}}",
        .{isolated_id},
    );
    defer testing.allocator.free(queue_isolated);
    bc.inspector_session.send(queue_isolated);

    // No contextId means the main context. Its queued callback runs, while the
    // isolated world's callback remains pending.
    try ctx.processMessage(.{ .id = 903, .method = "Runtime.evaluate", .params = .{ .expression = "0" } });
    try ctx.processMessage(.{ .id = 904, .method = "Runtime.evaluate", .params = .{ .contextId = main_id, .expression = "__mainDone" } });
    try ctx.expectSentResult(.{ .result = .{ .type = "boolean", .value = true } }, .{ .id = 904 });

    // The explicit isolated evaluation observes false before its own selected
    // checkpoint runs that world's queued callback.
    try ctx.processMessage(.{ .id = 905, .method = "Runtime.evaluate", .params = .{ .contextId = isolated_id, .expression = "__isolatedDone" } });
    try ctx.expectSentResult(.{ .result = .{ .type = "boolean", .value = false } }, .{ .id = 905 });
}

test "cdp.runtime: awaitPromise may remain pending without synthetic error" {
    var ctx = try testing.context();
    defer ctx.deinit();

    _ = try ctx.loadBrowserContext(.{ .id = "BID-AWAIT", .url = "hi.html", .target_id = "FID-0000000AWT".* });
    try ctx.processMessage(.{
        .id = 906,
        .method = "Runtime.evaluate",
        .params = .{
            .expression = "new Promise(() => {})",
            .awaitPromise = true,
        },
    });

    // Loading hi.html emits eight navigation events. An unresolved awaited
    // promise has no immediate response and must not be mistaken for termination.
    try ctx.expectSentCount(8);
}

test "cdp.runtime: delayed await response is not captured by later call" {
    var ctx = try testing.context();
    defer ctx.deinit();

    _ = try ctx.loadBrowserContext(.{ .id = "BID-DELAY", .url = "hi.html", .target_id = "FID-0000000DLY".* });
    try ctx.processMessage(.{
        .id = 908,
        .method = "Runtime.evaluate",
        .params = .{
            .expression = "new Promise(resolve => globalThis.__resolvePending = resolve)",
            .awaitPromise = true,
        },
    });

    // Resolving the earlier awaited promise causes its response to arrive while
    // call 909 is buffering its own response/checkpoint. The IDs must route
    // independently rather than asserting or overwriting the later response.
    try ctx.processMessage(.{
        .id = 909,
        .method = "Runtime.evaluate",
        .params = .{ .expression = "__resolvePending(41); 42" },
    });
    try ctx.expectSentResult(.{ .result = .{ .type = "number", .value = 41, .description = "41" } }, .{ .id = 908 });
    try ctx.expectSentResult(.{ .result = .{ .type = "number", .value = 42, .description = "42" } }, .{ .id = 909 });
    try ctx.expectSentCount(10);
}

test "cdp.runtime: target checkpoint watchdog replaces native response once" {
    var ctx = try testing.context();
    defer ctx.deinit();

    _ = try ctx.loadBrowserContext(.{ .id = "BID-TERM", .url = "hi.html", .target_id = "FID-0000000TRM".* });

    // Inspector evaluation itself completes, but its selected-context checkpoint
    // never drains because every microtask queues its successor. The watchdog must
    // discard that buffered success and emit one same-id termination error.
    try ctx.processMessage(.{
        .id = 907,
        .method = "Runtime.evaluate",
        .params = .{
            .expression = "queueMicrotask(function replenish(){queueMicrotask(replenish)}); 1",
        },
    });
    try ctx.expectSentError(-32000, "Execution was terminated", .{ .id = 907 });
    // Loading hi.html emits eight navigation events. The fallback must add
    // exactly one response, not the buffered native success or a generic error.
    try ctx.expectSentCount(9);
}

test "cdp.runtime: consoleAPICalled type matches the console method" {
    const filter: testing.LogFilter = .init(&.{.js});
    defer filter.deinit();

    // Wire types per the CDP protocol: console.log -> "log",
    // console.warn -> "warning" (not "warn"), console.info -> "info",
    // console.error -> "error", console.debug -> "debug".
    var ctx = try testing.context();
    defer ctx.deinit();

    var bc = try ctx.loadBrowserContext(.{ .id = "BID-CONS", .url = "hi.html", .target_id = "FID-0000000CON".* });
    try ctx.processMessage(.{ .id = 60, .method = "Runtime.enable" });

    const frame = bc.mainFrame() orelse unreachable;
    var ls: js.Local.Scope = undefined;
    frame.js.localScope(&ls);
    defer ls.deinit();
    _ = try ls.local.exec("console.log('l'); console.warn('w'); console.info('i'); console.error('e'); console.debug('d');", null);

    try ctx.expectSentEvent("Runtime.consoleAPICalled", .{ .type = "log" }, .{});
    try ctx.expectSentEvent("Runtime.consoleAPICalled", .{ .type = "warning" }, .{});
    try ctx.expectSentEvent("Runtime.consoleAPICalled", .{ .type = "info" }, .{});
    try ctx.expectSentEvent("Runtime.consoleAPICalled", .{ .type = "error" }, .{});
    try ctx.expectSentEvent("Runtime.consoleAPICalled", .{ .type = "debug" }, .{});
}
