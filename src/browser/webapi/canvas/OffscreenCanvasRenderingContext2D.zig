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
const Canvas = @import("../element/html/Canvas.zig");
const Image = @import("../element/html/Image.zig");
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
_state_stack: CanvasBitmap.DrawingStateStack = .{},
_global_alpha: f64 = 1.0,
_global_composite_operation: CanvasBitmap.CompositeOperation = .source_over,

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

pub fn getGlobalAlpha(self: *const OffscreenCanvasRenderingContext2D) f64 {
    return self._global_alpha;
}

pub fn setGlobalAlpha(self: *OffscreenCanvasRenderingContext2D, value: f64) void {
    if (CanvasBitmap.isValidGlobalAlpha(value)) {
        self._global_alpha = value;
        self.syncComposite();
    }
}

pub fn getGlobalCompositeOperation(self: *const OffscreenCanvasRenderingContext2D) []const u8 {
    return self._global_composite_operation.label();
}

pub fn setGlobalCompositeOperation(self: *OffscreenCanvasRenderingContext2D, value: []const u8) void {
    if (CanvasBitmap.CompositeOperation.parse(value)) |operation| {
        self._global_composite_operation = operation;
        self.syncComposite();
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

pub fn drawImage(
    self: *OffscreenCanvasRenderingContext2D,
    source_value: js.Value,
    dx: f64,
    dy: f64,
    arg3: ?f64,
    arg4: ?f64,
    arg5: ?f64,
    arg6: ?f64,
    arg7: ?f64,
    arg8: ?f64,
    exec: *Execution,
) !void {
    self.syncComposite();
    const source = resolveSourceBitmap(source_value) orelse return error.TypeError;
    try self._paint_stack.appendDrawImage(
        exec.arena,
        source,
        self._transform,
        dx,
        dy,
        arg3,
        arg4,
        arg5,
        arg6,
        arg7,
        arg8,
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

pub fn save(self: *OffscreenCanvasRenderingContext2D, exec: *const Execution) !void {
    try self._state_stack.push(exec.arena, CanvasBitmap.drawingState(self));
}

pub fn restore(self: *OffscreenCanvasRenderingContext2D) void {
    if (self._state_stack.pop()) |state| {
        CanvasBitmap.applyDrawingState(self, state);
    }
}
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
    self.syncComposite();
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
        self.syncComposite();
        self._paint_stack.appendStrokeRect(bounds.x, bounds.y, bounds.width, bounds.height, self._line_width * self._transform.strokeScale(), self._stroke_style);
    }
}
pub fn beginPath(self: *OffscreenCanvasRenderingContext2D) void {
    self._path.begin();
}
pub fn closePath(self: *OffscreenCanvasRenderingContext2D) void {
    self._path.closePath();
}
pub fn moveTo(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64) void {
    const point = self._transform.point(x, y);
    self._path.moveTo(point.x, point.y);
}
pub fn lineTo(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64) void {
    const point = self._transform.point(x, y);
    self._path.lineTo(point.x, point.y);
}
pub fn quadraticCurveTo(self: *OffscreenCanvasRenderingContext2D, cpx: f64, cpy: f64, x: f64, y: f64) void {
    const control = self._transform.point(cpx, cpy);
    const end = self._transform.point(x, y);
    self._path.quadraticCurveTo(control.x, control.y, end.x, end.y);
}
pub fn bezierCurveTo(self: *OffscreenCanvasRenderingContext2D, cp1x: f64, cp1y: f64, cp2x: f64, cp2y: f64, x: f64, y: f64) void {
    const control1 = self._transform.point(cp1x, cp1y);
    const control2 = self._transform.point(cp2x, cp2y);
    const end = self._transform.point(x, y);
    self._path.bezierCurveTo(control1.x, control1.y, control2.x, control2.y, end.x, end.y);
}
pub fn arc(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, radius: f64, start_angle: f64, end_angle: f64, maybe_counterclockwise: ?bool) void {
    const center = self._transform.point(x, y);
    self._path.arc(center.x, center.y, radius * self._transform.strokeScale(), start_angle, end_angle, maybe_counterclockwise);
}
pub fn arcTo(self: *OffscreenCanvasRenderingContext2D, x1: f64, y1: f64, x2: f64, y2: f64, radius: f64) void {
    const control = self._transform.point(x1, y1);
    const end = self._transform.point(x2, y2);
    self._path.arcTo(control.x, control.y, end.x, end.y, radius * self._transform.strokeScale());
}
pub fn rect(self: *OffscreenCanvasRenderingContext2D, x: f64, y: f64, width: f64, height: f64) void {
    if (self._transform.rect(x, y, width, height)) |bounds| {
        self._path.rect(bounds.x, bounds.y, bounds.width, bounds.height);
    }
}
pub fn fill(self: *OffscreenCanvasRenderingContext2D, maybe_fill_rule: ?[]const u8) void {
    self.syncComposite();
    self._paint_stack.appendPath(self._path, self._fill_style, maybe_fill_rule);
}
pub fn stroke(self: *OffscreenCanvasRenderingContext2D) void {
    self.syncComposite();
    self._paint_stack.appendStrokePath(self._path, self._line_width * self._transform.strokeScale(), self._stroke_style);
}
pub fn clip(self: *OffscreenCanvasRenderingContext2D, maybe_fill_rule: ?[]const u8) void {
    self._paint_stack.appendClip(self._path, maybe_fill_rule);
}
pub fn fillText(self: *OffscreenCanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64) void {
    self.syncComposite();
    const text_rect = CanvasBitmap.textFilledRect(text, x, y, max_width, self._fill_style, self._font) orelse return;
    if (self._transform.filledRect(text_rect)) |transformed| {
        self._paint_stack.appendRect(transformed);
    }
}
pub fn strokeText(self: *OffscreenCanvasRenderingContext2D, text: []const u8, x: f64, y: f64, max_width: ?f64) void {
    self.syncComposite();
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
pub fn isPointInStroke(self: *const OffscreenCanvasRenderingContext2D, x: f64, y: f64) bool {
    return CanvasBitmap.pathStrokeContains(self._path, x, y, self._line_width * self._transform.strokeScale());
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

pub fn sourceBitmap(self: *const OffscreenCanvasRenderingContext2D, width: u32, height: u32) CanvasBitmap.SourceBitmap {
    return .{
        .width = width,
        .height = height,
        .paint_stack = &self._paint_stack,
    };
}

fn resolveSourceBitmap(source_value: js.Value) ?CanvasBitmap.SourceBitmap {
    if (source_value.toZig(*Canvas)) |canvas| {
        return canvas.canvasSourceBitmap();
    } else |_| {}
    if (source_value.toZig(*OffscreenCanvas)) |canvas| {
        return canvas.canvasSourceBitmap();
    } else |_| {}
    if (source_value.toZig(*Image)) |img| {
        return img.imageSourceBitmap();
    } else |_| {}
    return null;
}

fn syncComposite(self: *OffscreenCanvasRenderingContext2D) void {
    self._paint_stack.setCurrentComposite(.{
        .alpha = self._global_alpha,
        .operation = self._global_composite_operation,
    });
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
    pub const globalAlpha = bridge.accessor(OffscreenCanvasRenderingContext2D.getGlobalAlpha, OffscreenCanvasRenderingContext2D.setGlobalAlpha, .{});
    pub const globalCompositeOperation = bridge.accessor(OffscreenCanvasRenderingContext2D.getGlobalCompositeOperation, OffscreenCanvasRenderingContext2D.setGlobalCompositeOperation, .{});
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
    pub const drawImage = bridge.function(OffscreenCanvasRenderingContext2D.drawImage, .{ .dom_exception = true });
    pub const getImageData = bridge.function(OffscreenCanvasRenderingContext2D.getImageData, .{ .dom_exception = true });
    pub const save = bridge.function(OffscreenCanvasRenderingContext2D.save, .{});
    pub const restore = bridge.function(OffscreenCanvasRenderingContext2D.restore, .{});
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
    pub const closePath = bridge.function(OffscreenCanvasRenderingContext2D.closePath, .{});
    pub const moveTo = bridge.function(OffscreenCanvasRenderingContext2D.moveTo, .{});
    pub const lineTo = bridge.function(OffscreenCanvasRenderingContext2D.lineTo, .{});
    pub const quadraticCurveTo = bridge.function(OffscreenCanvasRenderingContext2D.quadraticCurveTo, .{});
    pub const bezierCurveTo = bridge.function(OffscreenCanvasRenderingContext2D.bezierCurveTo, .{});
    pub const arc = bridge.function(OffscreenCanvasRenderingContext2D.arc, .{});
    pub const arcTo = bridge.function(OffscreenCanvasRenderingContext2D.arcTo, .{});
    pub const rect = bridge.function(OffscreenCanvasRenderingContext2D.rect, .{});
    pub const fill = bridge.function(OffscreenCanvasRenderingContext2D.fill, .{});
    pub const stroke = bridge.function(OffscreenCanvasRenderingContext2D.stroke, .{});
    pub const clip = bridge.function(OffscreenCanvasRenderingContext2D.clip, .{});
    pub const fillText = bridge.function(OffscreenCanvasRenderingContext2D.fillText, .{});
    pub const strokeText = bridge.function(OffscreenCanvasRenderingContext2D.strokeText, .{});
    pub const measureText = bridge.function(OffscreenCanvasRenderingContext2D.measureText, .{});
    pub const isPointInPath = bridge.function(OffscreenCanvasRenderingContext2D.isPointInPath, .{});
    pub const isPointInStroke = bridge.function(OffscreenCanvasRenderingContext2D.isPointInStroke, .{});
};
