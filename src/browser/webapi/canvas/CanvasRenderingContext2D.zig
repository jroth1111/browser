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
const Canvas = @import("../element/html/Canvas.zig");
const CanvasPath = @import("CanvasPath.zig");
const ImageData = @import("../ImageData.zig");
const Seeds = @import("../../../chimera/Seeds.zig");
const TextMetrics = @import("TextMetrics.zig");

const Execution = js.Execution;

/// This class doesn't implement a `constructor`.
/// It can be obtained with a call to `HTMLCanvasElement#getContext`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D
const CanvasRenderingContext2D = @This();
/// Reference to the parent canvas element.
/// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/canvas
_canvas: *Canvas,
/// Fill color.
/// TODO: Add support for `CanvasGradient` and `CanvasPattern`.
_fill_style: color.RGBA = color.RGBA.Named.black,
_font: []const u8 = CanvasBitmap.default_font,
_filled_rect: ?CanvasBitmap.FilledRect = null,
_path: CanvasPath = .{},

pub fn getCanvas(self: *const CanvasRenderingContext2D) *Canvas {
    return self._canvas;
}

pub fn getFillStyle(self: *const CanvasRenderingContext2D, exec: *Execution) ![]const u8 {
    var w = std.Io.Writer.Allocating.init(exec.call_arena);
    try self._fill_style.format(&w.writer);
    return w.written();
}

pub fn setFillStyle(
    self: *CanvasRenderingContext2D,
    value: []const u8,
) !void {
    // Prefer the same fill_style if fails.
    self._fill_style = color.RGBA.parse(value) catch self._fill_style;
}

pub fn getFont(self: *const CanvasRenderingContext2D) []const u8 {
    return self._font;
}

pub fn setFont(self: *CanvasRenderingContext2D, value: []const u8, exec: *const Execution) !void {
    if (value.len == 0) return;
    self._font = try exec.dupeString(value);
}

const WidthOrImageData = union(enum) {
    width: u32,
    image_data: *ImageData,
};

pub fn createImageData(
    _: *const CanvasRenderingContext2D,
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

pub fn putImageData(_: *const CanvasRenderingContext2D, _: *ImageData, _: f64, _: f64, _: ?f64, _: ?f64, _: ?f64, _: ?f64) void {}

// CanvasImageSource (HTMLImageElement, HTMLCanvasElement, ImageBitmap, ...) is
// just taken as a js.Value for now since we don't use it, and that's much easier.
pub fn drawImage(_: *const CanvasRenderingContext2D, _: js.Value, _: f64, _: f64, _: ?f64, _: ?f64, _: ?f64, _: ?f64, _: ?f64, _: ?f64) void {}

pub fn getImageData(
    self: *const CanvasRenderingContext2D,
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
            const rgba = self.pixelAt(
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

pub fn save(_: *CanvasRenderingContext2D) void {}
pub fn restore(_: *CanvasRenderingContext2D) void {}
pub fn scale(_: *CanvasRenderingContext2D, _: f64, _: f64) void {}
pub fn rotate(_: *CanvasRenderingContext2D, _: f64) void {}
pub fn translate(_: *CanvasRenderingContext2D, _: f64, _: f64) void {}
pub fn transform(_: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64, _: f64) void {}
pub fn setTransform(_: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64, _: f64) void {}
pub fn resetTransform(_: *CanvasRenderingContext2D) void {}
pub fn setStrokeStyle(_: *CanvasRenderingContext2D, _: []const u8) void {}
pub fn clearRect(self: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64) void {
    self._filled_rect = null;
}

pub fn fillRect(self: *CanvasRenderingContext2D, x: f64, y: f64, width: f64, height: f64) void {
    if (width <= 0 or height <= 0) return;
    self._filled_rect = .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .rgba = self._fill_style,
    };
}
pub fn strokeRect(_: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64) void {}
pub fn beginPath(self: *CanvasRenderingContext2D) void {
    self._path.begin();
}
pub fn closePath(_: *CanvasRenderingContext2D) void {}
pub fn moveTo(_: *CanvasRenderingContext2D, _: f64, _: f64) void {}
pub fn lineTo(_: *CanvasRenderingContext2D, _: f64, _: f64) void {}
pub fn quadraticCurveTo(_: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64) void {}
pub fn bezierCurveTo(_: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64, _: f64) void {}
pub fn arc(_: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64, _: ?bool) void {}
pub fn arcTo(_: *CanvasRenderingContext2D, _: f64, _: f64, _: f64, _: f64, _: f64) void {}
pub fn rect(self: *CanvasRenderingContext2D, x: f64, y: f64, width: f64, height: f64) void {
    self._path.rect(x, y, width, height);
}
pub fn fill(_: *CanvasRenderingContext2D) void {}
pub fn stroke(_: *CanvasRenderingContext2D) void {}
pub fn clip(_: *CanvasRenderingContext2D) void {}
pub fn fillText(self: *CanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64) void {
    self._filled_rect = CanvasBitmap.textFilledRect(text, x, y, max_width, self._fill_style, self._font);
}
pub fn strokeText(self: *CanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64) void {
    self._filled_rect = CanvasBitmap.textFilledRect(text, x, y, max_width, self._fill_style, self._font);
}
pub fn measureText(self: *const CanvasRenderingContext2D, text: []const u8, exec: *Execution) !*TextMetrics {
    const font_size = CanvasBitmap.fontPixelSize(self._font);
    return exec._factory.create(TextMetrics.init(CanvasBitmap.textWidth(text, self._font), font_size));
}
pub fn isPointInPath(self: *const CanvasRenderingContext2D, x: f64, y: f64, maybe_fill_rule: ?[]const u8) bool {
    return self._path.isPointInPath(x, y, maybe_fill_rule);
}
pub fn isPointInStroke(_: *const CanvasRenderingContext2D, _: f64, _: f64) bool {
    return false;
}

pub fn pngRawPixels(
    self: *const CanvasRenderingContext2D,
    allocator: std.mem.Allocator,
    seed: u64,
    width: u32,
    height: u32,
    raw_len: usize,
) ![]const u8 {
    return CanvasBitmap.rawPixelsForFilledRect(allocator, seed, width, height, raw_len, self._filled_rect);
}

fn pixelAt(self: *const CanvasRenderingContext2D, x: i64, y: i64, seed: u64) color.RGBA {
    return CanvasBitmap.pixelAt(self._filled_rect, x, y, seed);
}

fn canvasSeed(exec: *Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return 0;
    if (!authority.profile.canvas.enabled) return 0;
    return Seeds.surfaceSeed(&authority.profile, .canvas);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(CanvasRenderingContext2D);

    pub const Meta = struct {
        pub const name = "CanvasRenderingContext2D";

        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const canvas = bridge.accessor(CanvasRenderingContext2D.getCanvas, null, .{});
    pub const font = bridge.accessor(CanvasRenderingContext2D.getFont, CanvasRenderingContext2D.setFont, .{});
    pub const globalAlpha = bridge.property(1.0, .{ .template = false, .readonly = false });
    pub const globalCompositeOperation = bridge.property("source-over", .{ .template = false, .readonly = false });
    pub const strokeStyle = bridge.property("#000000", .{ .template = false, .readonly = false });
    pub const lineWidth = bridge.property(1.0, .{ .template = false, .readonly = false });
    pub const lineCap = bridge.property("butt", .{ .template = false, .readonly = false });
    pub const lineJoin = bridge.property("miter", .{ .template = false, .readonly = false });
    pub const miterLimit = bridge.property(10.0, .{ .template = false, .readonly = false });
    pub const textAlign = bridge.property("start", .{ .template = false, .readonly = false });
    pub const textBaseline = bridge.property("alphabetic", .{ .template = false, .readonly = false });

    pub const fillStyle = bridge.accessor(CanvasRenderingContext2D.getFillStyle, CanvasRenderingContext2D.setFillStyle, .{});
    pub const createImageData = bridge.function(CanvasRenderingContext2D.createImageData, .{ .dom_exception = true });

    pub const putImageData = bridge.function(CanvasRenderingContext2D.putImageData, .{ .noop = true });
    pub const drawImage = bridge.function(CanvasRenderingContext2D.drawImage, .{ .noop = true });
    pub const getImageData = bridge.function(CanvasRenderingContext2D.getImageData, .{ .dom_exception = true });
    pub const save = bridge.function(CanvasRenderingContext2D.save, .{ .noop = true });
    pub const restore = bridge.function(CanvasRenderingContext2D.restore, .{ .noop = true });
    pub const scale = bridge.function(CanvasRenderingContext2D.scale, .{ .noop = true });
    pub const rotate = bridge.function(CanvasRenderingContext2D.rotate, .{ .noop = true });
    pub const translate = bridge.function(CanvasRenderingContext2D.translate, .{ .noop = true });
    pub const transform = bridge.function(CanvasRenderingContext2D.transform, .{ .noop = true });
    pub const setTransform = bridge.function(CanvasRenderingContext2D.setTransform, .{ .noop = true });
    pub const resetTransform = bridge.function(CanvasRenderingContext2D.resetTransform, .{ .noop = true });
    pub const clearRect = bridge.function(CanvasRenderingContext2D.clearRect, .{});
    pub const fillRect = bridge.function(CanvasRenderingContext2D.fillRect, .{});
    pub const strokeRect = bridge.function(CanvasRenderingContext2D.strokeRect, .{ .noop = true });
    pub const beginPath = bridge.function(CanvasRenderingContext2D.beginPath, .{});
    pub const closePath = bridge.function(CanvasRenderingContext2D.closePath, .{ .noop = true });
    pub const moveTo = bridge.function(CanvasRenderingContext2D.moveTo, .{ .noop = true });
    pub const lineTo = bridge.function(CanvasRenderingContext2D.lineTo, .{ .noop = true });
    pub const quadraticCurveTo = bridge.function(CanvasRenderingContext2D.quadraticCurveTo, .{ .noop = true });
    pub const bezierCurveTo = bridge.function(CanvasRenderingContext2D.bezierCurveTo, .{ .noop = true });
    pub const arc = bridge.function(CanvasRenderingContext2D.arc, .{ .noop = true });
    pub const arcTo = bridge.function(CanvasRenderingContext2D.arcTo, .{ .noop = true });
    pub const rect = bridge.function(CanvasRenderingContext2D.rect, .{});
    pub const fill = bridge.function(CanvasRenderingContext2D.fill, .{ .noop = true });
    pub const stroke = bridge.function(CanvasRenderingContext2D.stroke, .{ .noop = true });
    pub const clip = bridge.function(CanvasRenderingContext2D.clip, .{ .noop = true });
    pub const fillText = bridge.function(CanvasRenderingContext2D.fillText, .{});
    pub const strokeText = bridge.function(CanvasRenderingContext2D.strokeText, .{});
    pub const measureText = bridge.function(CanvasRenderingContext2D.measureText, .{});
    pub const isPointInPath = bridge.function(CanvasRenderingContext2D.isPointInPath, .{});
    pub const isPointInStroke = bridge.function(CanvasRenderingContext2D.isPointInStroke, .{});
};

const testing = @import("../../../testing.zig");
test "WebApi: CanvasRenderingContext2D" {
    try testing.htmlRunner("canvas/canvas_rendering_context_2d.html", .{});
}
