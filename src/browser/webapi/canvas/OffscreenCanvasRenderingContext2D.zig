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

const js = @import("../../js/js.zig");
const color = @import("../../color.zig");

const CanvasBitmap = @import("CanvasBitmap.zig");
const CanvasPath = @import("CanvasPath.zig");
const ImageData = @import("../ImageData.zig");
const OffscreenCanvas = @import("OffscreenCanvas.zig");
const Seeds = @import("../../../chimera/Seeds.zig");
const TextMetrics = @import("TextMetrics.zig");

const Execution = js.Execution;

/// This class doesn't implement a `constructor`.
/// It can be obtained with a call to `OffscreenCanvas#getContext`.
/// https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvasRenderingContext2D
const OffscreenCanvasRenderingContext2D = @This();
_canvas: *OffscreenCanvas,
/// Fill color.
/// TODO: Add support for `CanvasGradient` and `CanvasPattern`.
_fill_style: color.RGBA = color.RGBA.Named.black,
_stroke_style: color.RGBA = color.RGBA.Named.black,
_line_width: f64 = 1.0,
_font: []const u8 = CanvasBitmap.default_font,
_paint_stack: CanvasBitmap.PaintStack = .{},
_path: CanvasPath = .{},
_transform: CanvasBitmap.Transform = .{},

pub fn getCanvas(self: *const OffscreenCanvasRenderingContext2D) *OffscreenCanvas {
    return self._canvas;
}

pub fn getFillStyle(self: *const OffscreenCanvasRenderingContext2D, exec: *Execution) ![]const u8 {
    var w = std.Io.Writer.Allocating.init(exec.call_arena);
    try self._fill_style.format(&w.writer);
    return w.written();
}

pub fn setFillStyle(
    self: *OffscreenCanvasRenderingContext2D,
    value: []const u8,
) !void {
    // Prefer the same fill_style if fails.
    self._fill_style = color.RGBA.parse(value) catch self._fill_style;
}

pub fn getStrokeStyle(self: *const OffscreenCanvasRenderingContext2D, exec: *Execution) ![]const u8 {
    var w = std.Io.Writer.Allocating.init(exec.call_arena);
    try self._stroke_style.format(&w.writer);
    return w.written();
}

pub fn setStrokeStyle(
    self: *OffscreenCanvasRenderingContext2D,
    value: []const u8,
) !void {
    self._stroke_style = color.RGBA.parse(value) catch self._stroke_style;
}

pub fn getLineWidth(self: *const OffscreenCanvasRenderingContext2D) f64 {
    return self._line_width;
}

pub fn setLineWidth(self: *OffscreenCanvasRenderingContext2D, value: f64) void {
    if (CanvasBitmap.isValidLineWidth(value)) {
        self._line_width = value;
    }
}

pub fn getFont(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return self._font;
}

pub fn setFont(self: *OffscreenCanvasRenderingContext2D, value: []const u8, exec: *const Execution) !void {
    if (!CanvasBitmap.isValidFont(value)) return;
    self._font = try exec.dupeString(value);
}

const WidthOrImageData = union(enum) {
    width: u32,
    image_data: *ImageData,
};

pub fn createImageData(
    _: *const OffscreenCanvasRenderingContext2D,
    width_or_image_data: WidthOrImageData,
    /// If `ImageData` variant preferred, this is null.
    maybe_height: ?u32,
    /// Can be used if width and height provided.
    maybe_settings: ?ImageData.ConstructorSettings,
    exec: *Execution,
) !*ImageData {
    switch (width_or_image_data) {
        .width => |width| {
            const height = maybe_height orelse return error.TypeError;
            return ImageData.init(width, height, maybe_settings, exec);
        },
        .image_data => |image_data| {
            return ImageData.init(image_data._width, image_data._height, null, exec);
        },
    }
}

pub fn putImageData(
    self: *OffscreenCanvasRenderingContext2D,
    image_data: *ImageData,
    dx: f64,
    dy: f64,
    dirty_x: ?f64,
    dirty_y: ?f64,
    dirty_width: ?f64,
    dirty_height: ?f64,
    exec: *Execution,
) !void {
    try self._paint_stack.appendImagePatch(
        exec.arena,
        image_data._width,
        image_data._height,
        image_data.pixelData(exec),
        dx,
        dy,
        dirty_x,
        dirty_y,
        dirty_width,
        dirty_height,
    );
}

pub fn getImageData(
    self: *const OffscreenCanvasRenderingContext2D,
    sx: i32,
    sy: i32,
    sw: i32,
    sh: i32,
    exec: *Execution,
) !*ImageData {
    if (sw <= 0 or sh <= 0) {
        return error.IndexSizeError;
    }
    const image_data = try ImageData.init(@as(u32, @intCast(sw)), @as(u32, @intCast(sh)), null, exec);
    const pixels = image_data.pixelData(exec);
    const width: usize = @intCast(sw);
    const height: usize = @intCast(sh);
    const sx_base: i64 = sx;
    const sy_base: i64 = sy;
    const seed = canvasSeed(exec);

    var pos: usize = 0;
    for (0..height) |y| {
        for (0..width) |x| {
            const rgba = CanvasBitmap.paintStackPixelAt(
                &self._paint_stack,
                sx_base + @as(i64, @intCast(x)),
                sy_base + @as(i64, @intCast(y)),
                seed,
            );
            pixels[pos + 0] = rgba.r;
            pixels[pos + 1] = rgba.g;
            pixels[pos + 2] = rgba.b;
            pixels[pos + 3] = rgba.a;
            pos += 4;
        }
    }

    return image_data;
}

pub fn save(_: *OffscreenCanvasRenderingContext2D) void {}
pub fn restore(_: *OffscreenCanvasRenderingContext2D) void {}
pub fn scale(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64) void {
    self._transform.scale(x, y);
}
pub fn rotate(self: *OffscreenCanvasRenderingContext2D, angle: f64) void {
    self._transform.rotate(angle);
}
pub fn translate(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64) void {
    self._transform.translate(x, y);
}
pub fn transform(self: *OffscreenCanvasRenderingContext2D, a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) void {
    self._transform.transform(a, b, c, d, e, f);
}
pub fn setTransform(self: *OffscreenCanvasRenderingContext2D, a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) void {
    self._transform.set(a, b, c, d, e, f);
}
pub fn resetTransform(self: *OffscreenCanvasRenderingContext2D) void {
    self._transform.reset();
}
pub fn clearRect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, width: f64, height: f64) void {
    if (self._transform.rect(x, y, width, height)) |bounds| {
        self._paint_stack.appendClearRect(bounds.x, bounds.y, bounds.width, bounds.height);
    }
}

pub fn fillRect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, width: f64, height: f64) void {
    if (width <= 0 or height <= 0) return;
    const transformed_rect = self._transform.filledRect(.{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .rgba = self._fill_style,
    }) orelse return;
    self._paint_stack.appendRect(transformed_rect);
}
pub fn strokeRect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, width: f64, height: f64) void {
    if (self._transform.rect(x, y, width, height)) |bounds| {
        self._paint_stack.appendStrokeRect(bounds.x, bounds.y, bounds.width, bounds.height, self._line_width * self._transform.strokeScale(), self._stroke_style);
    }
}
pub fn beginPath(self: *OffscreenCanvasRenderingContext2D) void {
    self._path.begin();
}
pub fn closePath(_: *OffscreenCanvasRenderingContext2D) void {}
pub fn moveTo(_: *OffscreenCanvasRenderingContext2D, _: f64, _: f64) void {}
pub fn lineTo(_: *OffscreenCanvasRenderingContext2D, _: f64, _: f64) void {}
pub fn quadraticCurveTo(_: *OffscreenCanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64) void {}
pub fn bezierCurveTo(_: *OffscreenCanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64, _: f64) void {}
pub fn arc(_: *OffscreenCanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64, _: ?bool) void {}
pub fn arcTo(_: *OffscreenCanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64) void {}
pub fn rect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, width: f64, height: f64) void {
    if (self._transform.rect(x, y, width, height)) |bounds| {
        self._path.rect(bounds.x, bounds.y, bounds.width, bounds.height);
    }
}
pub fn fill(self: *OffscreenCanvasRenderingContext2D, maybe_fill_rule: ?[]const u8) void {
    self._paint_stack.appendPath(self._path, self._fill_style, maybe_fill_rule);
}
pub fn stroke(_: *OffscreenCanvasRenderingContext2D) void {}
pub fn clip(_: *OffscreenCanvasRenderingContext2D) void {}
pub fn fillText(self: *OffscreenCanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64) void {
    const text_rect = CanvasBitmap.textFilledRect(text, x, y, max_width, self._fill_style, self._font) orelse return;
    if (self._transform.filledRect(text_rect)) |transformed| {
        self._paint_stack.appendRect(transformed);
    }
}
pub fn strokeText(self: *OffscreenCanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64) void {
    const text_rect = CanvasBitmap.textFilledRect(text, x, y, max_width, self._fill_style, self._font) orelse return;
    if (self._transform.filledRect(text_rect)) |transformed| {
        self._paint_stack.appendRect(transformed);
    }
}
pub fn measureText(self: *const OffscreenCanvasRenderingContext2D, text: []const u8, exec: *Execution) !*TextMetrics {
    const font_size = CanvasBitmap.fontPixelSize(self._font);
    return exec._factory.create(TextMetrics.init(CanvasBitmap.textWidth(text, self._font), font_size));
}
pub fn isPointInPath(self: *const OffscreenCanvasRenderingContext2D, x: f64, y: f64, maybe_fill_rule: ?[]const u8) bool {
    return self._path.isPointInPath(x, y, maybe_fill_rule);
}
pub fn isPointInStroke(_: *const OffscreenCanvasRenderingContext2D, _: f64, _: f64) bool {
    return false;
}

pub fn resetBitmap(self: *OffscreenCanvasRenderingContext2D) void {
    self._paint_stack.clear();
    self._path.begin();
}

pub fn pngRawPixels(
    self: *const OffscreenCanvasRenderingContext2D,
    allocator: std.mem.Allocator,
    seed: u64,
    width: u32,
    height: u32,
    raw_len: usize,
) ![]const u8 {
    return CanvasBitmap.rawPixelsForPaintStack(allocator, seed, width, height, raw_len, &self._paint_stack);
}

fn canvasSeed(exec: *Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return 0;
    if (!authority.profile.canvas.enabled) return 0;
    return Seeds.surfaceSeed(&authority.profile, .canvas);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(OffscreenCanvasRenderingContext2D);

    pub const Meta = struct {
        pub const name = "OffscreenCanvasRenderingContext2D";

        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const canvas = bridge.accessor(OffscreenCanvasRenderingContext2D.getCanvas, null, .{});
    pub const font = bridge.accessor(OffscreenCanvasRenderingContext2D.getFont, OffscreenCanvasRenderingContext2D.setFont, .{});
    pub const globalAlpha = bridge.property(1.0, .{ .template = false, .readonly = false });
    pub const globalCompositeOperation = bridge.property("source-over", .{ .template = false, .readonly = false });
    pub const strokeStyle = bridge.accessor(OffscreenCanvasRenderingContext2D.getStrokeStyle, OffscreenCanvasRenderingContext2D.setStrokeStyle, .{});
    pub const lineWidth = bridge.accessor(OffscreenCanvasRenderingContext2D.getLineWidth, OffscreenCanvasRenderingContext2D.setLineWidth, .{});
    pub const lineCap = bridge.property("butt", .{ .template = false, .readonly = false });
    pub const lineJoin = bridge.property("miter", .{ .template = false, .readonly = false });
    pub const miterLimit = bridge.property(10.0, .{ .template = false, .readonly = false });
    pub const textAlign = bridge.property("start", .{ .template = false, .readonly = false });
    pub const textBaseline = bridge.property("alphabetic", .{ .template = false, .readonly = false });

    pub const fillStyle = bridge.accessor(OffscreenCanvasRenderingContext2D.getFillStyle, OffscreenCanvasRenderingContext2D.setFillStyle, .{});
    pub const createImageData = bridge.function(OffscreenCanvasRenderingContext2D.createImageData, .{ .dom_exception = true });

    pub const putImageData = bridge.function(OffscreenCanvasRenderingContext2D.putImageData, .{});
    pub const getImageData = bridge.function(OffscreenCanvasRenderingContext2D.getImageData, .{ .dom_exception = true });
    pub const save = bridge.function(OffscreenCanvasRenderingContext2D.save, .{ .noop = true });
    pub const restore = bridge.function(OffscreenCanvasRenderingContext2D.restore, .{ .noop = true });
    pub const scale = bridge.function(OffscreenCanvasRenderingContext2D.scale, .{});
    pub const rotate = bridge.function(OffscreenCanvasRenderingContext2D.rotate, .{});
    pub const translate = bridge.function(OffscreenCanvasRenderingContext2D.translate, .{});
    pub const transform = bridge.function(OffscreenCanvasRenderingContext2D.transform, .{});
    pub const setTransform = bridge.function(OffscreenCanvasRenderingContext2D.setTransform, .{});
    pub const resetTransform = bridge.function(OffscreenCanvasRenderingContext2D.resetTransform, .{});
    pub const clearRect = bridge.function(OffscreenCanvasRenderingContext2D.clearRect, .{});
    pub const fillRect = bridge.function(OffscreenCanvasRenderingContext2D.fillRect, .{});
    pub const strokeRect = bridge.function(OffscreenCanvasRenderingContext2D.strokeRect, .{});
    pub const beginPath = bridge.function(OffscreenCanvasRenderingContext2D.beginPath, .{});
    pub const closePath = bridge.function(OffscreenCanvasRenderingContext2D.closePath, .{ .noop = true });
    pub const moveTo = bridge.function(OffscreenCanvasRenderingContext2D.moveTo, .{ .noop = true });
    pub const lineTo = bridge.function(OffscreenCanvasRenderingContext2D.lineTo, .{ .noop = true });
    pub const quadraticCurveTo = bridge.function(OffscreenCanvasRenderingContext2D.quadraticCurveTo, .{ .noop = true });
    pub const bezierCurveTo = bridge.function(OffscreenCanvasRenderingContext2D.bezierCurveTo, .{ .noop = true });
    pub const arc = bridge.function(OffscreenCanvasRenderingContext2D.arc, .{ .noop = true });
    pub const arcTo = bridge.function(OffscreenCanvasRenderingContext2D.arcTo, .{ .noop = true });
    pub const rect = bridge.function(OffscreenCanvasRenderingContext2D.rect, .{});
    pub const fill = bridge.function(OffscreenCanvasRenderingContext2D.fill, .{});
    pub const stroke = bridge.function(OffscreenCanvasRenderingContext2D.stroke, .{ .noop = true });
    pub const clip = bridge.function(OffscreenCanvasRenderingContext2D.clip, .{ .noop = true });
    pub const fillText = bridge.function(OffscreenCanvasRenderingContext2D.fillText, .{});
    pub const strokeText = bridge.function(OffscreenCanvasRenderingContext2D.strokeText, .{});
    pub const measureText = bridge.function(OffscreenCanvasRenderingContext2D.measureText, .{});
    pub const isPointInPath = bridge.function(OffscreenCanvasRenderingContext2D.isPointInPath, .{});
    pub const isPointInStroke = bridge.function(OffscreenCanvasRenderingContext2D.isPointInStroke, .{});
};
