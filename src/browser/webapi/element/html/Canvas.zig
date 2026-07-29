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
const js = @import("../../../js/js.zig");
const Frame = @import("../../../Frame.zig");
const Node = @import("../../Node.zig");
const Element = @import("../../Element.zig");
const HtmlElement = @import("../Html.zig");

const Blob = @import("../../Blob.zig");
const CanvasBitmap = @import("../../canvas/CanvasBitmap.zig");
const CanvasRenderingContext2D = @import("../../canvas/CanvasRenderingContext2D.zig");
const WebGLRenderingContext = @import("../../canvas/WebGLRenderingContext.zig");
const OffscreenCanvas = @import("../../canvas/OffscreenCanvas.zig");
const Seeds = @import("../../../../chimera/Seeds.zig");

const Execution = js.Execution;
const Allocator = std.mem.Allocator;

const Canvas = @This();
_proto: *HtmlElement,
_cached: ?DrawingContext = null,

pub fn asElement(self: *Canvas) *Element {
    return self._proto._proto;
}
pub fn asConstElement(self: *const Canvas) *const Element {
    return self._proto._proto;
}
pub fn asNode(self: *Canvas) *Node {
    return self.asElement().asNode();
}

pub fn getWidth(self: *const Canvas) u32 {
    const attr = self.asConstElement().getAttributeSafe(comptime .wrap("width")) orelse return 300;
    return std.fmt.parseUnsigned(u32, attr, 10) catch 300;
}

pub fn setWidth(self: *Canvas, value: u32, frame: *Frame) !void {
    const str = try std.fmt.allocPrint(frame.call_arena, "{d}", .{value});
    try self.asElement().setAttributeSafe(comptime .wrap("width"), .wrap(str), frame);
}

pub fn getHeight(self: *const Canvas) u32 {
    const attr = self.asConstElement().getAttributeSafe(comptime .wrap("height")) orelse return 150;
    return std.fmt.parseUnsigned(u32, attr, 10) catch 150;
}

pub fn setHeight(self: *Canvas, value: u32, frame: *Frame) !void {
    const str = try std.fmt.allocPrint(frame.call_arena, "{d}", .{value});
    try self.asElement().setAttributeSafe(comptime .wrap("height"), .wrap(str), frame);
}

/// Since there's no base class rendering contexts inherit from,
/// we're using tagged union.
const DrawingContext = union(enum) {
    @"2d": *CanvasRenderingContext2D,
    webgl: *WebGLRenderingContext,
};

pub fn getContext(self: *Canvas, context_type: []const u8, frame: *Frame) !?DrawingContext {
    if (self._cached) |cached| {
        const matches = switch (cached) {
            .@"2d" => std.mem.eql(u8, context_type, "2d"),
            .webgl => std.mem.eql(u8, context_type, "webgl") or std.mem.eql(u8, context_type, "experimental-webgl"),
        };
        return if (matches) cached else null;
    }

    const drawing_context: DrawingContext = blk: {
        if (std.mem.eql(u8, context_type, "2d")) {
            const ctx = try frame._factory.create(CanvasRenderingContext2D{ ._canvas = self });
            break :blk .{ .@"2d" = ctx };
        }

        if (std.mem.eql(u8, context_type, "webgl") or std.mem.eql(u8, context_type, "experimental-webgl")) {
            const width = self.getWidth();
            const height = self.getHeight();
            const authority = frame._session.browser.http_client.network.config.chimeraAuthority();
            const profile = if (authority) |loaded| &loaded.profile else null;
            const ctx = try frame._factory.create(WebGLRenderingContext.initFromProfile(width, height, profile));
            break :blk .{ .webgl = ctx };
        }
        return null;
    };
    self._cached = drawing_context;
    return drawing_context;
}

/// Transfers control of the canvas to an OffscreenCanvas.
/// Returns an OffscreenCanvas with the same dimensions.
pub fn transferControlToOffscreen(self: *Canvas, exec: *Execution) !*OffscreenCanvas {
    const width = self.getWidth();
    const height = self.getHeight();
    return OffscreenCanvas.constructor(width, height, exec);
}

pub fn toDataURL(self: *const Canvas, maybe_type: ?[]const u8, frame: *Frame) ![]const u8 {
    _ = maybe_type;

    const png = (try self.canvasPngBytes(frame.call_arena, frame)) orelse return "data:,";

    const encoder = std.base64.standard.Encoder;
    const prefix = "data:image/png;base64,";
    const encoded_size = encoder.calcSize(png.len);
    const out = try frame.call_arena.alloc(u8, prefix.len + encoded_size);
    @memcpy(out[0..prefix.len], prefix);
    _ = encoder.encode(out[prefix.len..], png);
    return out;
}

pub fn toBlob(
    self: *const Canvas,
    maybe_callback: ?js.Function.Temp,
    maybe_type: ?[]const u8,
    quality: ?f64,
    frame: *Frame,
) !void {
    _ = maybe_type;
    _ = quality;

    const callback = maybe_callback orelse return;
    errdefer callback.release();

    const arena = try frame.getArena(.tiny, "Canvas.toBlob");
    errdefer frame.releaseArena(arena);

    const task = try arena.create(ToBlobCallback);
    task.* = .{
        .canvas = self,
        .callback = callback,
        .frame = frame,
        .arena = arena,
    };

    try frame.js.scheduler.add(task, ToBlobCallback.run, 0, .{
        .name = "Canvas.toBlob",
        .low_priority = false,
        .finalizer = ToBlobCallback.cancelled,
    });
}

const ToBlobCallback = struct {
    canvas: *const Canvas,
    callback: js.Function.Temp,
    frame: *Frame,
    arena: Allocator,

    fn cancelled(ctx: *anyopaque) void {
        const self: *ToBlobCallback = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn deinit(self: *ToBlobCallback) void {
        self.callback.release();
        self.frame.releaseArena(self.arena);
    }

    fn run(ctx: *anyopaque) !?u32 {
        const self: *ToBlobCallback = @ptrCast(@alignCast(ctx));
        defer self.deinit();

        const frame = self.frame;
        const maybe_png = try self.canvas.canvasPngBytes(frame.call_arena, frame);
        const blob = if (maybe_png) |png|
            try Blob.initFromBytes(png, "image/png", frame._page)
        else
            null;

        var ls: js.Local.Scope = undefined;
        frame.js.localScope(&ls);
        defer ls.deinit();

        try ls.toLocal(self.callback).call(void, .{blob});
        ls.local.runMicrotasks();
        return null;
    }
};

fn canvasPngBytes(self: *const Canvas, allocator: Allocator, frame: *Frame) !?[]const u8 {
    const seed = canvasSeed(frame);
    const width = self.getWidth();
    const height = self.getHeight();
    if (width == 0 or height == 0) return null;

    const raw_len = CanvasBitmap.rawLen(width, height) orelse return null;
    if (raw_len > CanvasBitmap.max_png_raw_bytes) return null;
    const raw = try self.canvasRawPixels(allocator, seed, width, height, raw_len);
    return try CanvasBitmap.png(allocator, width, height, raw);
}

fn canvasSeed(frame: *Frame) u64 {
    const authority = frame._session.browser.http_client.network.config.chimeraAuthority() orelse return 0;
    if (!authority.profile.canvasNoiseEnabled()) return 0;
    return Seeds.surfaceSeed(&authority.profile, .canvas);
}

fn canvasRawPixels(self: *const Canvas, allocator: std.mem.Allocator, seed: u64, width: u32, height: u32, raw_len: usize) ![]const u8 {
    if (self._cached) |cached| {
        switch (cached) {
            .@"2d" => |ctx| return ctx.pngRawPixels(allocator, seed, width, height, raw_len),
            else => {},
        }
    }

    return CanvasBitmap.transparentRawPixels(allocator, width, height, raw_len);
}

pub fn canvasSourceBitmap(self: *const Canvas) ?CanvasBitmap.SourceBitmap {
    const width = self.getWidth();
    const height = self.getHeight();
    if (width == 0 or height == 0) return null;
    if (self._cached) |cached| {
        switch (cached) {
            .@"2d" => |ctx| return ctx.sourceBitmap(width, height),
            else => {},
        }
    }

    return .{ .width = width, .height = height, .paint_stack = null };
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Canvas);

    pub const Meta = struct {
        pub const name = "HTMLCanvasElement";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const width = bridge.accessor(Canvas.getWidth, Canvas.setWidth, .{ .ce_reactions = true });
    pub const height = bridge.accessor(Canvas.getHeight, Canvas.setHeight, .{ .ce_reactions = true });
    pub const getContext = bridge.function(Canvas.getContext, .{});
    pub const transferControlToOffscreen = bridge.function(Canvas.transferControlToOffscreen, .{});
    pub const toDataURL = bridge.function(Canvas.toDataURL, .{});
    pub const toBlob = bridge.function(Canvas.toBlob, .{});
};
