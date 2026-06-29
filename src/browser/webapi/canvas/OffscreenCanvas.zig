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
const js = @import("../../js/js.zig");

const Blob = @import("../Blob.zig");
const CanvasBitmap = @import("CanvasBitmap.zig");
const OffscreenCanvasRenderingContext2D = @import("OffscreenCanvasRenderingContext2D.zig");
const Seeds = @import("../../../chimera/Seeds.zig");

const Execution = js.Execution;
const Allocator = std.mem.Allocator;

/// https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvas
const OffscreenCanvas = @This();

pub const _prototype_root = true;

_width: u32,
_height: u32,
_cached: ?DrawingContext = null,

/// Since there's no base class rendering contexts inherit from,
/// we're using tagged union.
const DrawingContext = union(enum) {
    @"2d": *OffscreenCanvasRenderingContext2D,
};

pub fn constructor(width: u32, height: u32, exec: *Execution) !*OffscreenCanvas {
    return exec._factory.create(OffscreenCanvas{
        ._width = width,
        ._height = height,
        ._cached = null,
    });
}

pub fn getWidth(self: *const OffscreenCanvas) u32 {
    return self._width;
}

pub fn setWidth(self: *OffscreenCanvas, value: u32) void {
    self._width = value;
    self.resetBitmap();
}

pub fn getHeight(self: *const OffscreenCanvas) u32 {
    return self._height;
}

pub fn setHeight(self: *OffscreenCanvas, value: u32) void {
    self._height = value;
    self.resetBitmap();
}

pub fn getContext(self: *OffscreenCanvas, context_type: []const u8, exec: *Execution) !?DrawingContext {
    if (self._cached) |cached| {
        const matches = switch (cached) {
            .@"2d" => std.mem.eql(u8, context_type, "2d"),
        };
        return if (matches) cached else null;
    }

    if (std.mem.eql(u8, context_type, "2d")) {
        const ctx = try exec._factory.create(OffscreenCanvasRenderingContext2D{ ._canvas = self });
        const drawing_context: DrawingContext = .{ .@"2d" = ctx };
        self._cached = drawing_context;
        return drawing_context;
    }

    return null;
}

pub fn convertToBlob(self: *const OffscreenCanvas, exec: *Execution) !js.Promise {
    const maybe_png = try self.canvasPngBytes(exec.call_arena, exec);
    const blob = if (maybe_png) |png|
        try Blob.initFromBytes(png, "image/png", exec.page)
    else
        try Blob.init(null, null, exec.page);
    return exec.js.local.?.resolvePromise(blob);
}

/// Returns an ImageBitmap with the rendered content (stub).
pub fn transferToImageBitmap(_: *OffscreenCanvas) ?void {
    // ImageBitmap not implemented yet, return null
    return null;
}

fn resetBitmap(self: *OffscreenCanvas) void {
    if (self._cached) |cached| {
        switch (cached) {
            .@"2d" => |ctx| ctx.resetBitmap(),
        }
    }
}

fn canvasPngBytes(self: *const OffscreenCanvas, allocator: Allocator, exec: *Execution) !?[]const u8 {
    const seed = canvasSeed(exec);
    const width = self.getWidth();
    const height = self.getHeight();
    if (width == 0 or height == 0) return null;

    const raw_len = CanvasBitmap.rawLen(width, height) orelse return null;
    if (raw_len > CanvasBitmap.max_png_raw_bytes) return null;
    const raw = try self.canvasRawPixels(allocator, seed, width, height, raw_len);
    return try CanvasBitmap.png(allocator, width, height, raw);
}

fn canvasRawPixels(self: *const OffscreenCanvas, allocator: Allocator, seed: u64, width: u32, height: u32, raw_len: usize) ![]const u8 {
    if (self._cached) |cached| {
        switch (cached) {
            .@"2d" => |ctx| return ctx.pngRawPixels(allocator, seed, width, height, raw_len),
        }
    }

    return CanvasBitmap.transparentRawPixels(allocator, width, height, raw_len);
}

fn canvasSeed(exec: *Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return 0;
    if (!authority.profile.canvas.enabled) return 0;
    return Seeds.surfaceSeed(&authority.profile, .canvas);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(OffscreenCanvas);

    pub const Meta = struct {
        pub const name = "OffscreenCanvas";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(OffscreenCanvas.constructor, .{});
    pub const width = bridge.accessor(OffscreenCanvas.getWidth, OffscreenCanvas.setWidth, .{});
    pub const height = bridge.accessor(OffscreenCanvas.getHeight, OffscreenCanvas.setHeight, .{});
    pub const getContext = bridge.function(OffscreenCanvas.getContext, .{});
    pub const convertToBlob = bridge.function(OffscreenCanvas.convertToBlob, .{});
    pub const transferToImageBitmap = bridge.function(OffscreenCanvas.transferToImageBitmap, .{});
};

const testing = @import("../../../testing.zig");
test "WebApi: OffscreenCanvas" {
    try testing.htmlRunner("canvas/offscreen_canvas.html", .{});
}
