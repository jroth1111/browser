const std = @import("std");

const color = @import("../../color.zig");
const Seeds = @import("../../../chimera/Seeds.zig");
const CanvasPath = @import("CanvasPath.zig");

pub const max_png_raw_bytes = 4 * 1024 * 1024;
pub const max_paint_ops = 32;
pub const max_clip_masks = 16;
pub const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
pub const default_font = "10px sans-serif";

pub const Transform = struct {
    a: f64 = 1.0,
    b: f64 = 0.0,
    c: f64 = 0.0,
    d: f64 = 1.0,
    e: f64 = 0.0,
    f: f64 = 0.0,

    pub fn translate(self: *Transform, x: f64, y: f64) void {
        self.multiply(.{ .e = x, .f = y });
    }

    pub fn scale(self: *Transform, x: f64, y: f64) void {
        self.multiply(.{ .a = x, .d = y });
    }

    pub fn rotate(self: *Transform, angle: f64) void {
        if (!finite(angle)) return;
        const cos = @cos(angle);
        const sin = @sin(angle);
        self.multiply(.{ .a = cos, .b = sin, .c = -sin, .d = cos });
    }

    pub fn transform(self: *Transform, a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) void {
        self.multiply(.{ .a = a, .b = b, .c = c, .d = d, .e = e, .f = f });
    }

    pub fn set(self: *Transform, a: f64, b: f64, c: f64, d: f64, e: f64, f: f64) void {
        const next = Transform{ .a = a, .b = b, .c = c, .d = d, .e = e, .f = f };
        if (!next.valid()) return;
        self.* = next;
    }

    pub fn reset(self: *Transform) void {
        self.* = .{};
    }

    pub fn rect(self: Transform, x: f64, y: f64, width: f64, height: f64) ?RectBounds {
        if (!finite(x) or !finite(y) or !finite(width) or !finite(height)) return null;
        if (width == 0 or height == 0) return null;
        const p0 = self.point(x, y);
        const p1 = self.point(x + width, y);
        const p2 = self.point(x, y + height);
        const p3 = self.point(x + width, y + height);
        const left = @min(@min(p0.x, p1.x), @min(p2.x, p3.x));
        const right = @max(@max(p0.x, p1.x), @max(p2.x, p3.x));
        const top = @min(@min(p0.y, p1.y), @min(p2.y, p3.y));
        const bottom = @max(@max(p0.y, p1.y), @max(p2.y, p3.y));
        if (!finite(left) or !finite(right) or !finite(top) or !finite(bottom)) return null;
        if (left == right or top == bottom) return null;
        return .{ .x = left, .y = top, .width = right - left, .height = bottom - top };
    }

    pub fn filledRect(self: Transform, rect_in: FilledRect) ?FilledRect {
        const bounds = self.rect(rect_in.x, rect_in.y, rect_in.width, rect_in.height) orelse return null;
        return .{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width,
            .height = bounds.height,
            .rgba = rect_in.rgba,
        };
    }

    pub fn strokeScale(self: Transform) f64 {
        const x_scale = @sqrt(self.a * self.a + self.b * self.b);
        const y_scale = @sqrt(self.c * self.c + self.d * self.d);
        return @max(x_scale, y_scale);
    }

    fn multiply(self: *Transform, other: Transform) void {
        if (!other.valid() or !self.valid()) return;
        const next = Transform{
            .a = self.a * other.a + self.c * other.b,
            .b = self.b * other.a + self.d * other.b,
            .c = self.a * other.c + self.c * other.d,
            .d = self.b * other.c + self.d * other.d,
            .e = self.a * other.e + self.c * other.f + self.e,
            .f = self.b * other.e + self.d * other.f + self.f,
        };
        if (next.valid()) self.* = next;
    }

    fn valid(self: Transform) bool {
        return finite(self.a) and finite(self.b) and finite(self.c) and
            finite(self.d) and finite(self.e) and finite(self.f);
    }

    pub fn point(self: Transform, x: f64, y: f64) Point {
        return .{
            .x = self.a * x + self.c * y + self.e,
            .y = self.b * x + self.d * y + self.f,
        };
    }
};

pub const RectBounds = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

const Point = struct {
    x: f64,
    y: f64,
};

pub const DrawingState = struct {
    fill_style: color.RGBA,
    stroke_style: color.RGBA,
    line_width: f64,
    font: []const u8,
    transform: Transform,
    clip_bits: u16,
    global_alpha: f64,
    global_composite_operation: CompositeOperation,
};

pub const CompositeOperation = enum {
    source_over,
    copy,

    pub fn parse(value: []const u8) ?CompositeOperation {
        if (std.mem.eql(u8, value, "source-over")) return .source_over;
        if (std.mem.eql(u8, value, "copy")) return .copy;
        return null;
    }

    pub fn label(self: CompositeOperation) []const u8 {
        return switch (self) {
            .source_over => "source-over",
            .copy => "copy",
        };
    }
};

pub const CompositeState = struct {
    alpha: f64 = 1.0,
    operation: CompositeOperation = .source_over,
};

pub fn drawingState(context: anytype) DrawingState {
    return .{
        .fill_style = context._fill_style,
        .stroke_style = context._stroke_style,
        .line_width = context._line_width,
        .font = context._font,
        .transform = context._transform,
        .clip_bits = context._paint_stack.currentClipBits(),
        .global_alpha = context._global_alpha,
        .global_composite_operation = context._global_composite_operation,
    };
}

pub fn applyDrawingState(context: anytype, state: DrawingState) void {
    context._fill_style = state.fill_style;
    context._stroke_style = state.stroke_style;
    context._line_width = state.line_width;
    context._font = state.font;
    context._transform = state.transform;
    context._paint_stack.setCurrentClipBits(state.clip_bits);
    context._global_alpha = state.global_alpha;
    context._global_composite_operation = state.global_composite_operation;
    context._paint_stack.setCurrentComposite(.{
        .alpha = state.global_alpha,
        .operation = state.global_composite_operation,
    });
}

pub const DrawingStateStack = struct {
    states: std.ArrayListUnmanaged(DrawingState) = .{},

    pub fn push(self: *DrawingStateStack, allocator: std.mem.Allocator, state: DrawingState) !void {
        try self.states.append(allocator, state);
    }

    pub fn pop(self: *DrawingStateStack) ?DrawingState {
        if (self.states.items.len == 0) return null;
        const index = self.states.items.len - 1;
        const state = self.states.items[index];
        self.states.items.len = index;
        return state;
    }

    pub fn deinit(self: *DrawingStateStack, allocator: std.mem.Allocator) void {
        self.states.deinit(allocator);
        self.* = .{};
    }
};

pub const FilledRect = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    rgba: color.RGBA,

    fn contains(self: FilledRect, x: i64, y: i64) bool {
        const xf = @as(f64, @floatFromInt(x)) + 0.5;
        const yf = @as(f64, @floatFromInt(y)) + 0.5;
        return xf >= self.x and
            yf >= self.y and
            xf < self.x + self.width and
            yf < self.y + self.height;
    }
};

pub const ClearedRect = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,

    pub fn init(x: f64, y: f64, width: f64, height: f64) ?ClearedRect {
        if (!finite(x) or !finite(y) or !finite(width) or !finite(height)) return null;
        if (width == 0 or height == 0) return null;
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    fn contains(self: ClearedRect, x: i64, y: i64) bool {
        const xf = @as(f64, @floatFromInt(x)) + 0.5;
        const yf = @as(f64, @floatFromInt(y)) + 0.5;
        const left = @min(self.x, self.x + self.width);
        const right = @max(self.x, self.x + self.width);
        const top = @min(self.y, self.y + self.height);
        const bottom = @max(self.y, self.y + self.height);
        return xf >= left and
            xf < right and
            yf >= top and
            yf < bottom;
    }
};

pub const StrokedRect = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    line_width: f64,
    rgba: color.RGBA,

    pub fn init(x: f64, y: f64, width: f64, height: f64, line_width: f64, rgba: color.RGBA) ?StrokedRect {
        if (!finite(x) or !finite(y) or !finite(width) or !finite(height)) return null;
        if (!finite(line_width) or line_width <= 0) return null;
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .line_width = line_width,
            .rgba = rgba,
        };
    }

    fn contains(self: StrokedRect, x: i64, y: i64) bool {
        const xf = @as(f64, @floatFromInt(x)) + 0.5;
        const yf = @as(f64, @floatFromInt(y)) + 0.5;
        return self.containsPoint(xf, yf);
    }

    pub fn containsPoint(self: StrokedRect, xf: f64, yf: f64) bool {
        if (!finite(xf) or !finite(yf)) return false;
        const left = @min(self.x, self.x + self.width);
        const right = @max(self.x, self.x + self.width);
        const top = @min(self.y, self.y + self.height);
        const bottom = @max(self.y, self.y + self.height);
        const half = self.line_width / 2.0;
        const in_outer = xf >= left - half and
            xf < right + half and
            yf >= top - half and
            yf < bottom + half;
        if (!in_outer) return false;

        const inner_left = left + half;
        const inner_right = right - half;
        const inner_top = top + half;
        const inner_bottom = bottom - half;
        const has_inner = inner_left < inner_right and inner_top < inner_bottom;
        const in_inner = has_inner and
            xf >= inner_left and
            xf < inner_right and
            yf >= inner_top and
            yf < inner_bottom;
        return !in_inner;
    }
};

pub const FilledPath = struct {
    path: CanvasPath,
    rgba: color.RGBA,
    fill_rule: CanvasPath.FillRule,

    pub fn init(path: CanvasPath, rgba: color.RGBA, maybe_fill_rule: ?[]const u8) FilledPath {
        return .{
            .path = path,
            .rgba = rgba,
            .fill_rule = CanvasPath.parseFillRule(maybe_fill_rule),
        };
    }

    fn contains(self: *const FilledPath, x: i64, y: i64) bool {
        const xf = @as(f64, @floatFromInt(x)) + 0.5;
        const yf = @as(f64, @floatFromInt(y)) + 0.5;
        return self.path.contains(xf, yf, self.fill_rule);
    }
};

pub const StrokedPath = struct {
    path: CanvasPath,
    line_width: f64,
    rgba: color.RGBA,

    pub fn init(path: CanvasPath, line_width: f64, rgba: color.RGBA) ?StrokedPath {
        if (!finite(line_width) or line_width <= 0 or path.isEmpty()) return null;
        return .{
            .path = path,
            .line_width = line_width,
            .rgba = rgba,
        };
    }

    fn contains(self: *const StrokedPath, x: i64, y: i64) bool {
        const xf = @as(f64, @floatFromInt(x)) + 0.5;
        const yf = @as(f64, @floatFromInt(y)) + 0.5;
        return self.path.strokeContains(xf, yf, self.line_width);
    }
};

/// Rendered text as actual glyph shapes rather than a solid bounding box.
///
/// Each printable ASCII byte (0x20..0x7F) maps to an 8x8 bitmap in `font8x8`
/// (public-domain `font8x8_basic`; each byte is one row, bit 0 = leftmost
/// pixel). Non-ASCII (and bytes outside the table) fall back to a "tofu" box so
/// output still varies with content while degrading gracefully.
///
/// Glyphs are laid out in user space using exactly the per-character advances
/// that `textWidth`/`measureText` report, so positioning stays consistent. The
/// full current transform is honoured by inverse-mapping each queried device
/// pixel back into user space (this preserves rotation/skew that the old
/// axis-aligned bounding-box path discarded). `maxWidth` compresses the text
/// horizontally via `scale_x`, matching how the rectangle path clamped width.
pub const FilledText = struct {
    text: []const u8,
    /// Baseline origin in user space (alphabetic baseline).
    ox: f64,
    oy: f64,
    font_size: f64,
    /// Horizontal compression factor applied for `maxWidth` (1.0 = none).
    scale_x: f64,
    /// Forward (user -> device) transform; inverted per-pixel for hit testing.
    transform: Transform,
    /// Determinant of the transform linear part; guaranteed non-zero.
    det: f64,
    rgba: color.RGBA,

    // Fraction of font size used for the ascent (top of grid above baseline)
    // and descent (bottom of grid below baseline). Together they map the 8
    // bitmap rows onto the glyph cell height.
    const ascent_ratio = 0.75;
    const descent_ratio = 0.05;

    pub fn init(
        text: []const u8,
        x: f64,
        y: f64,
        max_width: ?f64,
        rgba: color.RGBA,
        font: []const u8,
        transform: Transform,
    ) ?FilledText {
        if (text.len == 0 or !finite(x) or !finite(y)) return null;
        const natural_width = textWidth(text, font);
        if (!(natural_width > 0)) return null;

        var scale_x: f64 = 1.0;
        if (max_width) |limit| {
            if (!finite(limit) or limit <= 0) return null;
            if (limit < natural_width) scale_x = limit / natural_width;
        }

        const det = transform.a * transform.d - transform.b * transform.c;
        if (!finite(det) or det == 0) return null;

        return .{
            .text = text,
            .ox = x,
            .oy = y,
            .font_size = fontPixelSize(font),
            .scale_x = scale_x,
            .transform = transform,
            .det = det,
            .rgba = rgba,
        };
    }

    fn pixelAt(self: *const FilledText, px: i64, py: i64) ?color.RGBA {
        // Sample at the pixel centre and inverse-transform into user space.
        const dx = @as(f64, @floatFromInt(px)) + 0.5;
        const dy = @as(f64, @floatFromInt(py)) + 0.5;
        const t = self.transform;
        const rx = dx - t.e;
        const ry = dy - t.f;
        const lx = (t.d * rx - t.c * ry) / self.det;
        const ly = (-t.b * rx + t.a * ry) / self.det;

        // Vertical: map the 8 bitmap rows onto [oy - ascent, oy + descent].
        const grid_top = self.oy - self.font_size * ascent_ratio;
        const grid_h = self.font_size * (ascent_ratio + descent_ratio);
        if (grid_h <= 0) return null;
        const row_f = (ly - grid_top) / grid_h * 8.0;
        if (row_f < 0 or row_f >= 8.0) return null;
        const row: usize = @intFromFloat(row_f);

        // Horizontal: undo maxWidth compression, then walk advances to find the
        // glyph cell the point falls into (mirrors `textWidth`).
        const nx = (lx - self.ox) / self.scale_x;
        if (nx < 0) return null;

        var cursor: f64 = 0;
        for (self.text) |byte| {
            if ((byte & 0xC0) == 0x80) continue; // UTF-8 continuation byte
            const advance = self.font_size * advanceFactor(byte);
            if (isSpace(byte)) {
                cursor += advance;
                continue;
            }
            if (nx >= cursor and nx < cursor + advance) {
                const col_f = (nx - cursor) / advance * 8.0;
                if (col_f < 0 or col_f >= 8.0) return null;
                const col: u3 = @intFromFloat(col_f);
                const glyph = glyphFor(byte);
                if ((glyph[row] >> col) & 1 == 1) return self.rgba;
                return null;
            }
            cursor += advance;
        }
        return null;
    }
};

fn isSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
}

fn advanceFactor(byte: u8) f64 {
    if (isSpace(byte)) return 0.25;
    return switch (byte) {
        0x00...0x7f => 0.48,
        else => 0.8,
    };
}

fn glyphFor(byte: u8) [8]u8 {
    if (byte >= 0x20 and byte <= 0x7f) return font8x8[byte - 0x20];
    // "tofu" box fallback for non-ASCII / untabled bytes.
    return .{ 0x00, 0x7e, 0x42, 0x42, 0x42, 0x42, 0x7e, 0x00 };
}

// Public-domain `font8x8_basic` (Daniel Hepper), printable ASCII 0x20..0x7F.
// One byte per row, bit 0 = leftmost pixel.
const font8x8 = [96][8]u8{
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ' '
    .{ 0x18, 0x3c, 0x3c, 0x18, 0x18, 0x00, 0x18, 0x00 }, // '!'
    .{ 0x36, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // '"'
    .{ 0x36, 0x36, 0x7f, 0x36, 0x7f, 0x36, 0x36, 0x00 }, // '#'
    .{ 0x0c, 0x3e, 0x03, 0x1e, 0x30, 0x1f, 0x0c, 0x00 }, // '$'
    .{ 0x00, 0x63, 0x33, 0x18, 0x0c, 0x66, 0x63, 0x00 }, // '%'
    .{ 0x1c, 0x36, 0x1c, 0x6e, 0x3b, 0x33, 0x6e, 0x00 }, // '&'
    .{ 0x06, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00 }, // '\''
    .{ 0x18, 0x0c, 0x06, 0x06, 0x06, 0x0c, 0x18, 0x00 }, // '('
    .{ 0x06, 0x0c, 0x18, 0x18, 0x18, 0x0c, 0x06, 0x00 }, // ')'
    .{ 0x00, 0x66, 0x3c, 0xff, 0x3c, 0x66, 0x00, 0x00 }, // '*'
    .{ 0x00, 0x0c, 0x0c, 0x3f, 0x0c, 0x0c, 0x00, 0x00 }, // '+'
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x0c, 0x06 }, // ','
    .{ 0x00, 0x00, 0x00, 0x3f, 0x00, 0x00, 0x00, 0x00 }, // '-'
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x0c, 0x00 }, // '.'
    .{ 0x60, 0x30, 0x18, 0x0c, 0x06, 0x03, 0x01, 0x00 }, // '/'
    .{ 0x3e, 0x63, 0x73, 0x7b, 0x6f, 0x67, 0x3e, 0x00 }, // '0'
    .{ 0x0c, 0x0e, 0x0c, 0x0c, 0x0c, 0x0c, 0x3f, 0x00 }, // '1'
    .{ 0x1e, 0x33, 0x30, 0x1c, 0x06, 0x33, 0x3f, 0x00 }, // '2'
    .{ 0x1e, 0x33, 0x30, 0x1c, 0x30, 0x33, 0x1e, 0x00 }, // '3'
    .{ 0x38, 0x3c, 0x36, 0x33, 0x7f, 0x30, 0x78, 0x00 }, // '4'
    .{ 0x3f, 0x03, 0x1f, 0x30, 0x30, 0x33, 0x1e, 0x00 }, // '5'
    .{ 0x1c, 0x06, 0x03, 0x1f, 0x33, 0x33, 0x1e, 0x00 }, // '6'
    .{ 0x3f, 0x33, 0x30, 0x18, 0x0c, 0x0c, 0x0c, 0x00 }, // '7'
    .{ 0x1e, 0x33, 0x33, 0x1e, 0x33, 0x33, 0x1e, 0x00 }, // '8'
    .{ 0x1e, 0x33, 0x33, 0x3e, 0x30, 0x18, 0x0e, 0x00 }, // '9'
    .{ 0x00, 0x0c, 0x0c, 0x00, 0x00, 0x0c, 0x0c, 0x00 }, // ':'
    .{ 0x00, 0x0c, 0x0c, 0x00, 0x00, 0x0c, 0x0c, 0x06 }, // ';'
    .{ 0x18, 0x0c, 0x06, 0x03, 0x06, 0x0c, 0x18, 0x00 }, // '<'
    .{ 0x00, 0x00, 0x3f, 0x00, 0x00, 0x3f, 0x00, 0x00 }, // '='
    .{ 0x06, 0x0c, 0x18, 0x30, 0x18, 0x0c, 0x06, 0x00 }, // '>'
    .{ 0x1e, 0x33, 0x30, 0x18, 0x0c, 0x00, 0x0c, 0x00 }, // '?'
    .{ 0x3e, 0x63, 0x7b, 0x7b, 0x7b, 0x03, 0x1e, 0x00 }, // '@'
    .{ 0x0c, 0x1e, 0x33, 0x33, 0x3f, 0x33, 0x33, 0x00 }, // 'A'
    .{ 0x3f, 0x66, 0x66, 0x3e, 0x66, 0x66, 0x3f, 0x00 }, // 'B'
    .{ 0x3c, 0x66, 0x03, 0x03, 0x03, 0x66, 0x3c, 0x00 }, // 'C'
    .{ 0x1f, 0x36, 0x66, 0x66, 0x66, 0x36, 0x1f, 0x00 }, // 'D'
    .{ 0x7f, 0x46, 0x16, 0x1e, 0x16, 0x46, 0x7f, 0x00 }, // 'E'
    .{ 0x7f, 0x46, 0x16, 0x1e, 0x16, 0x06, 0x0f, 0x00 }, // 'F'
    .{ 0x3c, 0x66, 0x03, 0x03, 0x73, 0x66, 0x7c, 0x00 }, // 'G'
    .{ 0x33, 0x33, 0x33, 0x3f, 0x33, 0x33, 0x33, 0x00 }, // 'H'
    .{ 0x1e, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x1e, 0x00 }, // 'I'
    .{ 0x78, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1e, 0x00 }, // 'J'
    .{ 0x67, 0x66, 0x36, 0x1e, 0x36, 0x66, 0x67, 0x00 }, // 'K'
    .{ 0x0f, 0x06, 0x06, 0x06, 0x46, 0x66, 0x7f, 0x00 }, // 'L'
    .{ 0x63, 0x77, 0x7f, 0x7f, 0x6b, 0x63, 0x63, 0x00 }, // 'M'
    .{ 0x63, 0x67, 0x6f, 0x7b, 0x73, 0x63, 0x63, 0x00 }, // 'N'
    .{ 0x1c, 0x36, 0x63, 0x63, 0x63, 0x36, 0x1c, 0x00 }, // 'O'
    .{ 0x3f, 0x66, 0x66, 0x3e, 0x06, 0x06, 0x0f, 0x00 }, // 'P'
    .{ 0x1e, 0x33, 0x33, 0x33, 0x3b, 0x1e, 0x38, 0x00 }, // 'Q'
    .{ 0x3f, 0x66, 0x66, 0x3e, 0x36, 0x66, 0x67, 0x00 }, // 'R'
    .{ 0x1e, 0x33, 0x07, 0x0e, 0x38, 0x33, 0x1e, 0x00 }, // 'S'
    .{ 0x3f, 0x2d, 0x0c, 0x0c, 0x0c, 0x0c, 0x1e, 0x00 }, // 'T'
    .{ 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x3f, 0x00 }, // 'U'
    .{ 0x33, 0x33, 0x33, 0x33, 0x33, 0x1e, 0x0c, 0x00 }, // 'V'
    .{ 0x63, 0x63, 0x63, 0x6b, 0x7f, 0x77, 0x63, 0x00 }, // 'W'
    .{ 0x63, 0x63, 0x36, 0x1c, 0x1c, 0x36, 0x63, 0x00 }, // 'X'
    .{ 0x33, 0x33, 0x33, 0x1e, 0x0c, 0x0c, 0x1e, 0x00 }, // 'Y'
    .{ 0x7f, 0x63, 0x31, 0x18, 0x4c, 0x66, 0x7f, 0x00 }, // 'Z'
    .{ 0x1e, 0x06, 0x06, 0x06, 0x06, 0x06, 0x1e, 0x00 }, // '['
    .{ 0x03, 0x06, 0x0c, 0x18, 0x30, 0x60, 0x40, 0x00 }, // '\\'
    .{ 0x1e, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1e, 0x00 }, // ']'
    .{ 0x08, 0x1c, 0x36, 0x63, 0x00, 0x00, 0x00, 0x00 }, // '^'
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff }, // '_'
    .{ 0x0c, 0x0c, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00 }, // '`'
    .{ 0x00, 0x00, 0x1e, 0x30, 0x3e, 0x33, 0x6e, 0x00 }, // 'a'
    .{ 0x07, 0x06, 0x06, 0x3e, 0x66, 0x66, 0x3b, 0x00 }, // 'b'
    .{ 0x00, 0x00, 0x1e, 0x33, 0x03, 0x33, 0x1e, 0x00 }, // 'c'
    .{ 0x38, 0x30, 0x30, 0x3e, 0x33, 0x33, 0x6e, 0x00 }, // 'd'
    .{ 0x00, 0x00, 0x1e, 0x33, 0x3f, 0x03, 0x1e, 0x00 }, // 'e'
    .{ 0x1c, 0x36, 0x06, 0x0f, 0x06, 0x06, 0x0f, 0x00 }, // 'f'
    .{ 0x00, 0x00, 0x6e, 0x33, 0x33, 0x3e, 0x30, 0x1f }, // 'g'
    .{ 0x07, 0x06, 0x36, 0x6e, 0x66, 0x66, 0x67, 0x00 }, // 'h'
    .{ 0x0c, 0x00, 0x0e, 0x0c, 0x0c, 0x0c, 0x1e, 0x00 }, // 'i'
    .{ 0x30, 0x00, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1e }, // 'j'
    .{ 0x07, 0x06, 0x66, 0x36, 0x1e, 0x36, 0x67, 0x00 }, // 'k'
    .{ 0x0e, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x1e, 0x00 }, // 'l'
    .{ 0x00, 0x00, 0x33, 0x7f, 0x7f, 0x6b, 0x63, 0x00 }, // 'm'
    .{ 0x00, 0x00, 0x1f, 0x33, 0x33, 0x33, 0x33, 0x00 }, // 'n'
    .{ 0x00, 0x00, 0x1e, 0x33, 0x33, 0x33, 0x1e, 0x00 }, // 'o'
    .{ 0x00, 0x00, 0x3b, 0x66, 0x66, 0x3e, 0x06, 0x0f }, // 'p'
    .{ 0x00, 0x00, 0x6e, 0x33, 0x33, 0x3e, 0x30, 0x78 }, // 'q'
    .{ 0x00, 0x00, 0x3b, 0x6e, 0x66, 0x06, 0x0f, 0x00 }, // 'r'
    .{ 0x00, 0x00, 0x3e, 0x03, 0x1e, 0x30, 0x1f, 0x00 }, // 's'
    .{ 0x08, 0x0c, 0x3e, 0x0c, 0x0c, 0x2c, 0x18, 0x00 }, // 't'
    .{ 0x00, 0x00, 0x33, 0x33, 0x33, 0x33, 0x6e, 0x00 }, // 'u'
    .{ 0x00, 0x00, 0x33, 0x33, 0x33, 0x1e, 0x0c, 0x00 }, // 'v'
    .{ 0x00, 0x00, 0x63, 0x6b, 0x7f, 0x7f, 0x36, 0x00 }, // 'w'
    .{ 0x00, 0x00, 0x63, 0x36, 0x1c, 0x36, 0x63, 0x00 }, // 'x'
    .{ 0x00, 0x00, 0x33, 0x33, 0x33, 0x3e, 0x30, 0x1f }, // 'y'
    .{ 0x00, 0x00, 0x3f, 0x19, 0x0c, 0x26, 0x3f, 0x00 }, // 'z'
    .{ 0x38, 0x0c, 0x0c, 0x07, 0x0c, 0x0c, 0x38, 0x00 }, // '{'
    .{ 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x00 }, // '|'
    .{ 0x07, 0x0c, 0x0c, 0x38, 0x0c, 0x0c, 0x07, 0x00 }, // '}'
    .{ 0x6e, 0x3b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // '~'
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // 0x7f
};

pub const ClipMask = struct {
    path: CanvasPath,
    fill_rule: CanvasPath.FillRule,

    pub fn init(path: CanvasPath, maybe_fill_rule: ?[]const u8) ?ClipMask {
        if (path.isEmpty()) return null;
        return .{
            .path = path,
            .fill_rule = CanvasPath.parseFillRule(maybe_fill_rule),
        };
    }

    fn contains(self: *const ClipMask, x: i64, y: i64) bool {
        const xf = @as(f64, @floatFromInt(x)) + 0.5;
        const yf = @as(f64, @floatFromInt(y)) + 0.5;
        return self.path.contains(xf, yf, self.fill_rule);
    }
};

pub const Paint = union(enum) {
    rect: FilledRect,
    clear_rect: ClearedRect,
    stroke_rect: StrokedRect,
    path: FilledPath,
    stroke_path: StrokedPath,
    text: FilledText,
    image: ImagePatch,

    fn pixelAt(self: *const Paint, x: i64, y: i64) ?color.RGBA {
        return switch (self.*) {
            .rect => |rect| if (rect.contains(x, y)) rect.rgba else null,
            .clear_rect => |rect| if (rect.contains(x, y)) color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 } else null,
            .stroke_rect => |rect| if (rect.contains(x, y)) rect.rgba else null,
            .path => |path| if (path.contains(x, y)) path.rgba else null,
            .stroke_path => |path| if (path.contains(x, y)) path.rgba else null,
            .text => |*t| t.pixelAt(x, y),
            .image => |image| image.pixelAt(x, y),
        };
    }

    /// Whether this op's pixels are freshly rasterized vector content (and so
    /// should receive the seeded anti-tracking noise) versus already
    /// materialized/copied pixel bytes (an `.image` patch from `drawImage` or
    /// `putImageData`, which may already carry noise baked in from an earlier
    /// materialization -- e.g. a `toDataURL` PNG encode -- and must not be
    /// perturbed again on every subsequent read). See `noisyChannel` below.
    fn noiseEligible(self: *const Paint) bool {
        return switch (self.*) {
            .image => false,
            else => true,
        };
    }
};

const PaintOp = struct {
    paint: Paint,
    clip_bits: u16,
    composite: CompositeState,
};

pub const ImagePatch = struct {
    x: i64,
    y: i64,
    width: u32,
    height: u32,
    data: []const u8,

    fn pixelAt(self: ImagePatch, x: i64, y: i64) ?color.RGBA {
        if (x < self.x or y < self.y) return null;
        const rel_x: u64 = @intCast(x - self.x);
        const rel_y: u64 = @intCast(y - self.y);
        if (rel_x >= @as(u64, self.width) or rel_y >= @as(u64, self.height)) return null;

        const pos: usize = @intCast(((rel_y * self.width) + rel_x) * 4);
        return .{
            .r = self.data[pos + 0],
            .g = self.data[pos + 1],
            .b = self.data[pos + 2],
            .a = self.data[pos + 3],
        };
    }
};

pub const SourceBitmap = struct {
    width: u32,
    height: u32,
    paint_stack: ?*const PaintStack = null,
    static_pixels: ?[]const u8 = null,
};

fn staticPixelAt(pixels: []const u8, width: u32, x: i64, y: i64) color.RGBA {
    const rel_x: u64 = @intCast(x);
    const rel_y: u64 = @intCast(y);
    const pos: usize = @intCast(((rel_y * width) + rel_x) * 4);
    return .{
        .r = pixels[pos + 0],
        .g = pixels[pos + 1],
        .b = pixels[pos + 2],
        .a = pixels[pos + 3],
    };
}

pub const PaintStack = struct {
    ops: [max_paint_ops]PaintOp = undefined,
    count: usize = 0,
    clip_masks: [max_clip_masks]ClipMask = undefined,
    clip_count: usize = 0,
    current_clip_bits: u16 = 0,
    current_composite: CompositeState = .{},

    pub fn clear(self: *PaintStack) void {
        self.count = 0;
        self.clip_count = 0;
        self.current_clip_bits = 0;
        self.current_composite = .{};
    }

    pub fn appendRect(self: *PaintStack, rect: FilledRect) void {
        self.append(.{ .rect = rect });
    }

    pub fn appendClearRect(self: *PaintStack, x: f64, y: f64, width: f64, height: f64) void {
        if (ClearedRect.init(x, y, width, height)) |rect| {
            self.appendWithComposite(.{ .clear_rect = rect }, .{ .operation = .copy });
        }
    }

    pub fn appendStrokeRect(self: *PaintStack, x: f64, y: f64, width: f64, height: f64, line_width: f64, rgba: color.RGBA) void {
        if (StrokedRect.init(x, y, width, height, line_width, rgba)) |rect| {
            self.append(.{ .stroke_rect = rect });
        }
    }

    pub fn appendStrokePath(self: *PaintStack, path: CanvasPath, line_width: f64, rgba: color.RGBA) void {
        if (StrokedPath.init(path, line_width, rgba)) |stroked_path| {
            self.append(.{ .stroke_path = stroked_path });
        }
    }

    /// Render `text` as glyph shapes under `transform`. `text` must outlive the
    /// paint stack (callers dup into the page arena).
    pub fn appendFilledText(self: *PaintStack, text: []const u8, x: f64, y: f64, max_width: ?f64, rgba: color.RGBA, font: []const u8, transform: Transform) void {
        if (FilledText.init(text, x, y, max_width, rgba, font, transform)) |glyphs| {
            self.append(.{ .text = glyphs });
        }
    }

    pub fn appendPath(self: *PaintStack, path: CanvasPath, rgba: color.RGBA, maybe_fill_rule: ?[]const u8) void {
        if (path.isEmpty()) return;
        self.append(.{ .path = FilledPath.init(path, rgba, maybe_fill_rule) });
    }

    pub fn appendClip(self: *PaintStack, path: CanvasPath, maybe_fill_rule: ?[]const u8) void {
        const mask = ClipMask.init(path, maybe_fill_rule) orelse return;
        if (self.clip_count >= max_clip_masks) return;
        self.clip_masks[self.clip_count] = mask;
        self.current_clip_bits |= @as(u16, 1) << @as(u4, @intCast(self.clip_count));
        self.clip_count += 1;
    }

    pub fn currentClipBits(self: *const PaintStack) u16 {
        return self.current_clip_bits;
    }

    pub fn setCurrentClipBits(self: *PaintStack, bits: u16) void {
        self.current_clip_bits = bits & activeClipMask(self.clip_count);
    }

    pub fn currentComposite(self: *const PaintStack) CompositeState {
        return self.current_composite;
    }

    pub fn setCurrentComposite(self: *PaintStack, state: CompositeState) void {
        self.current_composite = .{
            .alpha = if (isValidGlobalAlpha(state.alpha)) state.alpha else 1.0,
            .operation = state.operation,
        };
    }

    pub fn appendImagePatch(
        self: *PaintStack,
        allocator: std.mem.Allocator,
        image_width: u32,
        image_height: u32,
        pixels: []const u8,
        dx: f64,
        dy: f64,
        dirty_x: ?f64,
        dirty_y: ?f64,
        dirty_width: ?f64,
        dirty_height: ?f64,
    ) !void {
        const patch = try imagePatch(
            allocator,
            image_width,
            image_height,
            pixels,
            dx,
            dy,
            dirty_x,
            dirty_y,
            dirty_width,
            dirty_height,
        ) orelse return;
        self.appendWithComposite(.{ .image = patch }, .{ .operation = .copy });
    }

    pub fn appendDrawImage(
        self: *PaintStack,
        allocator: std.mem.Allocator,
        source: SourceBitmap,
        transform: Transform,
        seed: u64,
        dx: f64,
        dy: f64,
        arg3: ?f64,
        arg4: ?f64,
        arg5: ?f64,
        arg6: ?f64,
        arg7: ?f64,
        arg8: ?f64,
    ) !void {
        const resolved = drawImageRects(source, transform, dx, dy, arg3, arg4, arg5, arg6, arg7, arg8) orelse return;
        const patch_len = try pixelBytesLen(resolved.dst.width, resolved.dst.height);
        if (patch_len > max_png_raw_bytes) return;

        const data = try allocator.alloc(u8, patch_len);
        var row: u32 = 0;
        var pos: usize = 0;
        while (row < resolved.dst.height) : (row += 1) {
            const src_y = resolved.src.y + @divTrunc(@as(i64, @intCast(row)) * resolved.src.height, @as(i64, @intCast(resolved.dst.height)));
            var col: u32 = 0;
            while (col < resolved.dst.width) : (col += 1) {
                const src_x = resolved.src.x + @divTrunc(@as(i64, @intCast(col)) * resolved.src.width, @as(i64, @intCast(resolved.dst.width)));
                const rgba = if (src_x < 0 or src_y < 0 or
                    src_x >= @as(i64, @intCast(source.width)) or
                    src_y >= @as(i64, @intCast(source.height)))
                    color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 }
                else if (source.paint_stack) |paint_stack|
                    // Sampling a live canvas's paint stack as a `drawImage`
                    // source materializes those pixels into concrete copied
                    // bytes right here -- bake the noise in now (once), same
                    // as a direct `getImageData`/`toDataURL` read of the
                    // source would. The resulting `.image` patch below is
                    // then noise-ineligible, so it is never perturbed again.
                    paintStackPixelAt(paint_stack, src_x, src_y, seed)
                else if (source.static_pixels) |pixels|
                    staticPixelAt(pixels, source.width, src_x, src_y)
                else
                    color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 };
                data[pos + 0] = rgba.r;
                data[pos + 1] = rgba.g;
                data[pos + 2] = rgba.b;
                data[pos + 3] = rgba.a;
                pos += 4;
            }
        }

        self.append(.{ .image = .{
            .x = resolved.dst.x,
            .y = resolved.dst.y,
            .width = resolved.dst.width,
            .height = resolved.dst.height,
            .data = data,
        } });
    }

    fn append(self: *PaintStack, paint: Paint) void {
        self.appendWithComposite(paint, self.current_composite);
    }

    fn appendWithComposite(self: *PaintStack, paint: Paint, composite: CompositeState) void {
        const op = PaintOp{
            .paint = paint,
            .clip_bits = self.current_clip_bits,
            .composite = composite,
        };
        if (self.count < max_paint_ops) {
            self.ops[self.count] = op;
            self.count += 1;
            return;
        }

        var i: usize = 1;
        while (i < max_paint_ops) : (i += 1) {
            self.ops[i - 1] = self.ops[i];
        }
        self.ops[max_paint_ops - 1] = op;
    }

    /// Composites this stack's ops at `(x, y)`. `seed` (0 = disabled) applies
    /// the anti-tracking noise to each *vector* op's contribution before it is
    /// blended into the running composite -- i.e. at the point that op's pixel
    /// is actually rasterized -- so noise is baked in exactly once per pixel
    /// regardless of how many times this stack is later read, copied via
    /// `drawImage`, or PNG-encoded via `toDataURL`. `.image` ops (already
    /// materialized/copied pixel bytes) are never perturbed here; see
    /// `Paint.noiseEligible`.
    fn basePixelAt(self: *const PaintStack, x: i64, y: i64, seed: u64) color.RGBA {
        var rgba = color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 };
        for (self.ops[0..self.count]) |*op| {
            if (!self.clipContains(op.clip_bits, x, y)) continue;
            if (op.paint.pixelAt(x, y)) |painted| {
                const source = if (seed != 0 and painted.a != 0 and op.paint.noiseEligible())
                    noisePixel(painted, seed, x, y)
                else
                    painted;
                rgba = compositePixel(rgba, source, op.composite);
            }
        }
        return rgba;
    }

    fn clipContains(self: *const PaintStack, clip_bits: u16, x: i64, y: i64) bool {
        if (clip_bits == 0) return true;
        var i: usize = 0;
        while (i < self.clip_count) : (i += 1) {
            const bit = @as(u16, 1) << @as(u4, @intCast(i));
            if ((clip_bits & bit) == 0) continue;
            if (!self.clip_masks[i].contains(x, y)) return false;
        }
        return true;
    }
};

fn activeClipMask(count: usize) u16 {
    if (count == 0) return 0;
    if (count >= max_clip_masks) return std.math.maxInt(u16);
    return (@as(u16, 1) << @as(u4, @intCast(count))) - 1;
}

const SourceRect = struct {
    x: i64,
    y: i64,
    width: i64,
    height: i64,
};

const DestRect = struct {
    x: i64,
    y: i64,
    width: u32,
    height: u32,
};

const DrawImageRects = struct {
    src: SourceRect,
    dst: DestRect,
};

fn drawImageRects(
    source: SourceBitmap,
    transform: Transform,
    dx: f64,
    dy: f64,
    arg3: ?f64,
    arg4: ?f64,
    arg5: ?f64,
    arg6: ?f64,
    arg7: ?f64,
    arg8: ?f64,
) ?DrawImageRects {
    if (source.width == 0 or source.height == 0) return null;

    var sx: f64 = 0;
    var sy: f64 = 0;
    var sw: f64 = @floatFromInt(source.width);
    var sh: f64 = @floatFromInt(source.height);
    var dest_x = dx;
    var dest_y = dy;
    var dest_width = sw;
    var dest_height = sh;

    if (arg3 == null and arg4 == null and arg5 == null and arg6 == null and arg7 == null and arg8 == null) {
        // drawImage(image, dx, dy)
    } else if (arg3 != null and arg4 != null and arg5 == null and arg6 == null and arg7 == null and arg8 == null) {
        dest_width = arg3.?;
        dest_height = arg4.?;
    } else if (arg3 != null and arg4 != null and arg5 != null and arg6 != null and arg7 != null and arg8 != null) {
        sx = dx;
        sy = dy;
        sw = arg3.?;
        sh = arg4.?;
        dest_x = arg5.?;
        dest_y = arg6.?;
        dest_width = arg7.?;
        dest_height = arg8.?;
    } else {
        return null;
    }

    const src = normalizedSourceRect(sx, sy, sw, sh) orelse return null;
    const dst = transformedDestRect(transform, dest_x, dest_y, dest_width, dest_height) orelse return null;
    return .{ .src = src, .dst = dst };
}

fn normalizedSourceRect(x: f64, y: f64, width: f64, height: f64) ?SourceRect {
    var rect_x = finiteInteger(x) orelse return null;
    var rect_y = finiteInteger(y) orelse return null;
    var rect_width = finiteInteger(width) orelse return null;
    var rect_height = finiteInteger(height) orelse return null;

    if (rect_width < 0) {
        if (rect_width == std.math.minInt(i64)) return null;
        rect_x = checkedAddI64(rect_x, rect_width) orelse return null;
        rect_width = -rect_width;
    }
    if (rect_height < 0) {
        if (rect_height == std.math.minInt(i64)) return null;
        rect_y = checkedAddI64(rect_y, rect_height) orelse return null;
        rect_height = -rect_height;
    }
    if (rect_width == 0 or rect_height == 0) return null;

    return .{
        .x = rect_x,
        .y = rect_y,
        .width = rect_width,
        .height = rect_height,
    };
}

fn transformedDestRect(transform: Transform, x: f64, y: f64, width: f64, height: f64) ?DestRect {
    const bounds = transform.rect(x, y, width, height) orelse return null;
    return .{
        .x = finiteInteger(bounds.x) orelse return null,
        .y = finiteInteger(bounds.y) orelse return null,
        .width = positiveDimension(bounds.width) orelse return null,
        .height = positiveDimension(bounds.height) orelse return null,
    };
}

pub fn imagePatch(
    allocator: std.mem.Allocator,
    image_width: u32,
    image_height: u32,
    pixels: []const u8,
    dx: f64,
    dy: f64,
    dirty_x: ?f64,
    dirty_y: ?f64,
    dirty_width: ?f64,
    dirty_height: ?f64,
) !?ImagePatch {
    const dest_x = finiteInteger(dx) orelse return null;
    const dest_y = finiteInteger(dy) orelse return null;
    const required_len = try pixelBytesLen(image_width, image_height);
    if (pixels.len < required_len) return null;

    var source_x: i64 = 0;
    var source_y: i64 = 0;
    var source_width: i64 = @intCast(image_width);
    var source_height: i64 = @intCast(image_height);

    if (dirty_x != null or dirty_y != null or dirty_width != null or dirty_height != null) {
        source_x = finiteInteger(dirty_x orelse return null) orelse return null;
        source_y = finiteInteger(dirty_y orelse return null) orelse return null;
        source_width = finiteInteger(dirty_width orelse return null) orelse return null;
        source_height = finiteInteger(dirty_height orelse return null) orelse return null;
    }

    if (source_width < 0) {
        if (source_width == std.math.minInt(i64)) return null;
        source_x = checkedAddI64(source_x, source_width) orelse return null;
        source_width = -source_width;
    }
    if (source_height < 0) {
        if (source_height == std.math.minInt(i64)) return null;
        source_y = checkedAddI64(source_y, source_height) orelse return null;
        source_height = -source_height;
    }
    if (source_width == 0 or source_height == 0) return null;

    const left = @max(source_x, 0);
    const top = @max(source_y, 0);
    const right = @min(positiveEndI64(source_x, source_width), @as(i64, image_width));
    const bottom = @min(positiveEndI64(source_y, source_height), @as(i64, image_height));
    if (right <= left or bottom <= top) return null;

    const patch_width: u32 = @intCast(right - left);
    const patch_height: u32 = @intCast(bottom - top);
    const patch_len = try pixelBytesLen(patch_width, patch_height);
    const data = try allocator.alloc(u8, patch_len);

    const image_stride = @as(usize, image_width) * 4;
    const patch_stride = @as(usize, patch_width) * 4;
    var row: usize = 0;
    while (row < patch_height) : (row += 1) {
        const src_y = @as(usize, @intCast(top)) + row;
        const src_x = @as(usize, @intCast(left));
        const src_pos = src_y * image_stride + src_x * 4;
        const dst_pos = row * patch_stride;
        @memcpy(data[dst_pos..][0..patch_stride], pixels[src_pos..][0..patch_stride]);
    }

    const patch_x = checkedAddI64(dest_x, left) orelse return null;
    const patch_y = checkedAddI64(dest_y, top) orelse return null;

    return .{
        .x = patch_x,
        .y = patch_y,
        .width = patch_width,
        .height = patch_height,
        .data = data,
    };
}

pub fn parsedFontPixelSize(font: []const u8) ?f64 {
    var i: usize = 0;
    while (i + 1 < font.len) : (i += 1) {
        if (asciiLower(font[i]) != 'p' or asciiLower(font[i + 1]) != 'x') continue;
        var start = i;
        while (start > 0) {
            const ch = font[start - 1];
            if (!((ch >= '0' and ch <= '9') or ch == '.')) break;
            start -= 1;
        }
        if (start == i) continue;
        if (!hasFontSizeTokenBoundary(font, start)) continue;
        const parsed = std.fmt.parseFloat(f64, font[start..i]) catch continue;
        if (finite(parsed) and parsed > 0 and hasFontFamily(font, i + 2)) return parsed;
    }
    return null;
}

pub fn isValidFont(font: []const u8) bool {
    return parsedFontPixelSize(font) != null;
}

pub fn fontPixelSize(font: []const u8) f64 {
    return parsedFontPixelSize(font) orelse 10.0;
}

pub fn isValidLineWidth(value: f64) bool {
    return finite(value) and value > 0;
}

pub fn isValidGlobalAlpha(value: f64) bool {
    return finite(value) and value >= 0 and value <= 1;
}

pub fn pathStrokeContains(path: CanvasPath, x: f64, y: f64, line_width: f64) bool {
    return path.strokeContains(x, y, line_width);
}

pub fn textWidth(text: []const u8, font: []const u8) f64 {
    const font_size = fontPixelSize(font);
    var width: f64 = 0;
    for (text) |byte| {
        if ((byte & 0xC0) == 0x80) continue;
        width += font_size * advanceFactor(byte);
    }
    return width;
}

pub fn textFilledRect(text: []const u8, x: f64, y: f64, max_width: ?f64, rgba: color.RGBA, font: []const u8) ?FilledRect {
    if (text.len == 0 or !finite(x) or !finite(y)) return null;
    var width = textWidth(text, font);
    if (max_width) |limit| {
        if (!finite(limit) or limit <= 0) return null;
        width = @min(width, limit);
    }
    if (width <= 0) return null;
    const height = @max(1.0, fontPixelSize(font) * 0.75);
    return .{
        .x = x,
        .y = y - height,
        .width = width,
        .height = height,
        .rgba = rgba,
    };
}

pub fn rawLen(width: u32, height: u32) ?usize {
    const row_len = std.math.mul(u64, width, 4) catch return null;
    const raw_len = std.math.mul(u64, row_len + 1, height) catch return null;
    if (raw_len > std.math.maxInt(usize)) return null;
    return @intCast(raw_len);
}

fn pixelBytesLen(width: u32, height: u32) !usize {
    const pixels = try std.math.mul(u64, width, height);
    const bytes = try std.math.mul(u64, pixels, 4);
    if (bytes > std.math.maxInt(usize)) return error.Overflow;
    return @intCast(bytes);
}

fn finite(value: f64) bool {
    return !std.math.isNan(value) and !std.math.isInf(value);
}

fn finiteInteger(value: f64) ?i64 {
    if (!finite(value)) return null;
    if (value <= @as(f64, @floatFromInt(std.math.minInt(i64)))) return null;
    if (value >= @as(f64, @floatFromInt(std.math.maxInt(i64)))) return null;
    return @intFromFloat(@trunc(value));
}

fn positiveDimension(value: f64) ?u32 {
    if (!finite(value)) return null;
    if (value <= 0) return null;
    if (value > @as(f64, @floatFromInt(std.math.maxInt(u32)))) return null;
    const dimension: u64 = @intFromFloat(@trunc(value));
    if (dimension == 0 or dimension > std.math.maxInt(u32)) return null;
    return @intCast(dimension);
}

fn compositePixel(destination: color.RGBA, source: color.RGBA, composite: CompositeState) color.RGBA {
    return switch (composite.operation) {
        .copy => applyGlobalAlpha(source, composite.alpha),
        .source_over => sourceOver(destination, source, composite.alpha),
    };
}

fn applyGlobalAlpha(source: color.RGBA, alpha: f64) color.RGBA {
    return .{
        .r = source.r,
        .g = source.g,
        .b = source.b,
        .a = roundU8(@as(f64, @floatFromInt(source.a)) * alpha),
    };
}

fn sourceOver(destination: color.RGBA, source: color.RGBA, global_alpha: f64) color.RGBA {
    const src_a = (@as(f64, @floatFromInt(source.a)) / 255.0) * global_alpha;
    const dst_a = @as(f64, @floatFromInt(destination.a)) / 255.0;
    const out_a = src_a + dst_a * (1.0 - src_a);
    if (out_a <= 0) return .{ .r = 0, .g = 0, .b = 0, .a = 0 };

    return .{
        .r = blendChannel(source.r, destination.r, src_a, dst_a, out_a),
        .g = blendChannel(source.g, destination.g, src_a, dst_a, out_a),
        .b = blendChannel(source.b, destination.b, src_a, dst_a, out_a),
        .a = roundU8(out_a * 255.0),
    };
}

fn blendChannel(source: u8, destination: u8, src_a: f64, dst_a: f64, out_a: f64) u8 {
    const src = @as(f64, @floatFromInt(source));
    const dst = @as(f64, @floatFromInt(destination));
    return roundU8((src * src_a + dst * dst_a * (1.0 - src_a)) / out_a);
}

fn roundU8(value: f64) u8 {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return @intFromFloat(@round(value));
}

fn checkedAddI64(a: i64, b: i64) ?i64 {
    return std.math.add(i64, a, b) catch null;
}

fn positiveEndI64(start: i64, len: i64) i64 {
    std.debug.assert(len >= 0);
    return std.math.add(i64, start, len) catch std.math.maxInt(i64);
}

fn hasFontFamily(font: []const u8, after_px: usize) bool {
    if (after_px >= font.len) return false;

    var i = after_px;
    if (font[i] != '/' and !asciiWhitespace(font[i])) return false;

    while (i < font.len and asciiWhitespace(font[i])) : (i += 1) {}
    if (i < font.len and font[i] == '/') {
        i = skipLineHeight(font, i + 1) orelse return false;
    }

    while (i < font.len and asciiWhitespace(font[i])) : (i += 1) {}
    return i < font.len;
}

fn hasFontSizeTokenBoundary(font: []const u8, start: usize) bool {
    return start == 0 or asciiWhitespace(font[start - 1]);
}

fn skipLineHeight(font: []const u8, after_slash: usize) ?usize {
    var i = after_slash;
    while (i < font.len and asciiWhitespace(font[i])) : (i += 1) {}
    const start = i;
    while (i < font.len and !asciiWhitespace(font[i])) : (i += 1) {}
    if (i == start) return null;
    return i;
}

fn asciiLower(byte: u8) u8 {
    return switch (byte) {
        'A'...'Z' => byte + ('a' - 'A'),
        else => byte,
    };
}

fn asciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0c => true,
        else => false,
    };
}

pub fn transparentRawPixels(allocator: std.mem.Allocator, width: u32, height: u32, raw_len: usize) ![]const u8 {
    const out = try allocator.alloc(u8, raw_len);
    var pos: usize = 0;
    for (0..height) |_| {
        out[pos] = 0;
        pos += 1;
        for (0..width) |_| {
            out[pos + 0] = 0;
            out[pos + 1] = 0;
            out[pos + 2] = 0;
            out[pos + 3] = 0;
            pos += 4;
        }
    }
    return out;
}

pub fn rawPixelsForFilledRect(
    allocator: std.mem.Allocator,
    seed: u64,
    width: u32,
    height: u32,
    raw_len: usize,
    filled_rect: ?FilledRect,
) ![]const u8 {
    var stack = PaintStack{};
    if (filled_rect) |rect| stack.appendRect(rect);
    return rawPixelsForPaintStack(allocator, seed, width, height, raw_len, &stack);
}

pub fn rawPixelsForPaintStack(
    allocator: std.mem.Allocator,
    seed: u64,
    width: u32,
    height: u32,
    raw_len: usize,
    paint_stack: *const PaintStack,
) ![]const u8 {
    const out = try allocator.alloc(u8, raw_len);
    var pos: usize = 0;
    for (0..height) |y| {
        out[pos] = 0;
        pos += 1;
        for (0..width) |x| {
            const rgba = paintStackPixelAt(paint_stack, @as(i64, @intCast(x)), @as(i64, @intCast(y)), seed);
            out[pos + 0] = rgba.r;
            out[pos + 1] = rgba.g;
            out[pos + 2] = rgba.b;
            out[pos + 3] = rgba.a;
            pos += 4;
        }
    }
    return out;
}

pub fn pixelAt(filled_rect: ?FilledRect, x: i64, y: i64, seed: u64) color.RGBA {
    var stack = PaintStack{};
    if (filled_rect) |rect| stack.appendRect(rect);
    return paintStackPixelAt(&stack, x, y, seed);
}

pub fn paintStackPixelAt(paint_stack: *const PaintStack, x: i64, y: i64, seed: u64) color.RGBA {
    return paint_stack.basePixelAt(x, y, seed);
}

pub fn png(allocator: std.mem.Allocator, width: u32, height: u32, raw: []const u8) ![]const u8 {
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8;
    ihdr[9] = 6;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;

    const idat = try zlibStore(allocator, raw);
    const png_len = png_signature.len + pngChunkLen(ihdr.len) + pngChunkLen(idat.len) + pngChunkLen(0);
    const out = try allocator.alloc(u8, png_len);
    var pos: usize = 0;
    @memcpy(out[pos..][0..png_signature.len], &png_signature);
    pos += png_signature.len;
    appendPngChunk(out, &pos, "IHDR", &ihdr);
    appendPngChunk(out, &pos, "IDAT", idat);
    appendPngChunk(out, &pos, "IEND", "");
    return out;
}

/// Applies `noisyChannel` to each color channel of a freshly-rasterized
/// vector op's pixel. Alpha passes through untouched -- noise only ever
/// perturbs color, never coverage.
fn noisePixel(rgba: color.RGBA, seed: u64, x: i64, y: i64) color.RGBA {
    return .{
        .r = noisyChannel(rgba.r, seed, x, y, 0),
        .g = noisyChannel(rgba.g, seed, x, y, 1),
        .b = noisyChannel(rgba.b, seed, x, y, 2),
        .a = rgba.a,
    };
}

fn noisyChannel(value: u8, seed: u64, x: i64, y: i64, channel: u8) u8 {
    const ux: u64 = @bitCast(x);
    const uy: u64 = @bitCast(y);
    const rotated_y = (uy << 17) | (uy >> 47);
    const mixed = Seeds.mix(seed, ux ^ rotated_y ^ (@as(u64, channel) << 56));
    const delta = @as(i16, @intCast(mixed % 3)) - 1;
    const adjusted = @as(i16, @intCast(value)) + delta;
    if (adjusted <= 0) return 0;
    if (adjusted >= 255) return 255;
    return @intCast(adjusted);
}

fn pngChunkLen(payload_len: usize) usize {
    return 12 + payload_len;
}

fn appendPngChunk(out: []u8, pos: *usize, tag: []const u8, payload: []const u8) void {
    std.debug.assert(tag.len == 4);
    std.mem.writeInt(u32, out[pos.*..][0..4], @intCast(payload.len), .big);
    pos.* += 4;
    @memcpy(out[pos.*..][0..4], tag);
    pos.* += 4;
    @memcpy(out[pos.*..][0..payload.len], payload);
    pos.* += payload.len;
    std.mem.writeInt(u32, out[pos.*..][0..4], pngCrc(tag, payload), .big);
    pos.* += 4;
}

fn pngCrc(tag: []const u8, payload: []const u8) u32 {
    var crc = std.hash.Crc32.init();
    crc.update(tag);
    crc.update(payload);
    return crc.final();
}

fn zlibStore(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const block_count = (raw.len + 65534) / 65535;
    const out = try allocator.alloc(u8, 2 + raw.len + block_count * 5 + 4);
    var pos: usize = 0;
    out[pos] = 0x78;
    out[pos + 1] = 0x01;
    pos += 2;

    var raw_pos: usize = 0;
    while (raw_pos < raw.len) {
        const block_len = @min(raw.len - raw_pos, 65535);
        const final_block = raw_pos + block_len == raw.len;
        out[pos] = if (final_block) 1 else 0;
        pos += 1;
        std.mem.writeInt(u16, out[pos..][0..2], @intCast(block_len), .little);
        pos += 2;
        std.mem.writeInt(u16, out[pos..][0..2], ~@as(u16, @intCast(block_len)), .little);
        pos += 2;
        @memcpy(out[pos..][0..block_len], raw[raw_pos..][0..block_len]);
        pos += block_len;
        raw_pos += block_len;
    }
    std.mem.writeInt(u32, out[pos..][0..4], adler32(raw), .big);
    return out;
}

fn adler32(bytes: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    for (bytes) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

const testing = std.testing;

test "CanvasBitmap text metrics follow pixel font size" {
    const small = textWidth("Chimera", default_font);
    const large = textWidth("Chimera", "bold 48px serif");

    try testing.expect(small > 0);
    try testing.expect(large > small);
    try testing.expectEqual(@as(?f64, 48.0), parsedFontPixelSize("bold 48px serif"));
    try testing.expectEqual(@as(?f64, 16.0), parsedFontPixelSize("16px/1.2 Arial"));
    try testing.expectEqual(@as(?f64, 16.0), parsedFontPixelSize("16px /1.2 Arial"));
    try testing.expectEqual(@as(?f64, 18.0), parsedFontPixelSize("18PX / 1.2 Arial"));
    try testing.expectEqual(@as(?f64, null), parsedFontPixelSize("bold 1.2em serif"));
    try testing.expectEqual(@as(?f64, null), parsedFontPixelSize("16px"));
    try testing.expectEqual(@as(?f64, null), parsedFontPixelSize("16px /1.2"));
    try testing.expectEqual(@as(?f64, null), parsedFontPixelSize("16px / 1.2"));
    try testing.expectEqual(@as(?f64, null), parsedFontPixelSize("16pxArial"));
    try testing.expectEqual(@as(?f64, null), parsedFontPixelSize("12pt/16px Arial"));
    try testing.expectEqual(@as(?f64, null), parsedFontPixelSize("bold48px serif"));
    try testing.expectEqual(@as(f64, 10.0), fontPixelSize("bold 1.2em serif"));
}

test "CanvasBitmap text filled rect respects max width" {
    const rect = textFilledRect("Chimera", 2, 22, 6, color.RGBA.Named.black, "16px Arial").?;

    try testing.expectEqual(@as(f64, 2.0), rect.x);
    try testing.expectEqual(@as(f64, 6.0), rect.width);
    try testing.expect(rect.height > 1);
    try testing.expect(rect.contains(5, 12));
    try testing.expect(!rect.contains(12, 12));
}

test "CanvasBitmap stroke rect paints outline only" {
    var stack = PaintStack{};
    const blue = color.RGBA{ .r = 0, .g = 51, .b = 255, .a = 255 };

    stack.appendStrokeRect(4, 4, 8, 6, 2, blue);

    try testing.expectEqual(blue, paintStackPixelAt(&stack, 4, 4, 0));
    try testing.expectEqual(blue, paintStackPixelAt(&stack, 11, 9, 0));
    try testing.expectEqual(color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 }, paintStackPixelAt(&stack, 8, 7, 0));
    try testing.expectEqual(color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 }, paintStackPixelAt(&stack, 20, 20, 0));

    stack.appendStrokeRect(0, 0, 10, 10, 0, blue);
    try testing.expectEqual(@as(usize, 1), stack.count);
}

test "CanvasBitmap path stroke reuses stroke rect outline" {
    var stack = PaintStack{};
    var path = CanvasPath{};
    const blue = color.RGBA{ .r = 0, .g = 51, .b = 255, .a = 255 };

    path.rect(4, 4, 8, 6);
    stack.appendStrokePath(path, 2, blue);

    try testing.expectEqual(blue, paintStackPixelAt(&stack, 4, 4, 0));
    try testing.expectEqual(blue, paintStackPixelAt(&stack, 11, 9, 0));
    try testing.expectEqual(color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 }, paintStackPixelAt(&stack, 8, 7, 0));
    try testing.expect(pathStrokeContains(path, 4, 4, 2));
    try testing.expect(!pathStrokeContains(path, 8, 7, 2));
    try testing.expect(!pathStrokeContains(path, 4, 4, 0));
}

test "CanvasBitmap drawing state stack restores latest state" {
    var stack = DrawingStateStack{};
    defer stack.deinit(testing.allocator);
    const red = color.RGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = color.RGBA{ .r = 0, .g = 51, .b = 255, .a = 255 };
    const state = DrawingState{
        .fill_style = red,
        .stroke_style = blue,
        .line_width = 2,
        .font = "16px Arial",
        .transform = .{ .e = 4, .f = 3 },
        .clip_bits = 0,
        .global_alpha = 0.5,
        .global_composite_operation = .copy,
    };

    try testing.expect(stack.pop() == null);
    try stack.push(testing.allocator, state);
    const restored = stack.pop().?;
    try testing.expectEqual(red, restored.fill_style);
    try testing.expectEqual(blue, restored.stroke_style);
    try testing.expectEqual(@as(f64, 2), restored.line_width);
    try testing.expectEqualStrings("16px Arial", restored.font);
    try testing.expectEqual(@as(f64, 4), restored.transform.e);
    try testing.expectEqual(@as(f64, 3), restored.transform.f);
    try testing.expectEqual(@as(f64, 0.5), restored.global_alpha);
    try testing.expectEqual(CompositeOperation.copy, restored.global_composite_operation);
    try testing.expect(stack.pop() == null);
}

test "CanvasBitmap drawing state stack keeps deep state without a shallow cap" {
    var stack = DrawingStateStack{};
    defer stack.deinit(testing.allocator);

    for (0..64) |i| {
        try stack.push(testing.allocator, .{
            .fill_style = color.RGBA{ .r = @intCast(i), .g = 0, .b = 0, .a = 255 },
            .stroke_style = color.RGBA.Named.black,
            .line_width = @floatFromInt(i + 1),
            .font = default_font,
            .transform = .{ .e = @floatFromInt(i) },
            .clip_bits = 0,
            .global_alpha = 1.0,
            .global_composite_operation = .source_over,
        });
    }

    var next: usize = 64;
    while (next > 0) {
        next -= 1;
        const restored = stack.pop().?;
        try testing.expectEqual(@as(u8, @intCast(next)), restored.fill_style.r);
        try testing.expectEqual(@as(f64, @floatFromInt(next + 1)), restored.line_width);
        try testing.expectEqual(@as(f64, @floatFromInt(next)), restored.transform.e);
    }
    try testing.expect(stack.pop() == null);
}

test "CanvasBitmap clear rect overrides only covered pixels" {
    var stack = PaintStack{};
    const red = color.RGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };

    stack.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = red });
    stack.appendClearRect(4, 4, 2, 2);

    try testing.expectEqual(red, paintStackPixelAt(&stack, 1, 1, 0));
    try testing.expectEqual(color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 }, paintStackPixelAt(&stack, 4, 4, 0));
    try testing.expectEqual(red, paintStackPixelAt(&stack, 7, 7, 0));

    stack.appendClearRect(0, 0, 10, 10);
    try testing.expectEqual(color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 }, paintStackPixelAt(&stack, 1, 1, 0));
}

test "CanvasBitmap global alpha blends source over destination" {
    var stack = PaintStack{};
    const red = color.RGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = color.RGBA{ .r = 0, .g = 0, .b = 255, .a = 255 };

    stack.appendRect(.{ .x = 0, .y = 0, .width = 4, .height = 4, .rgba = red });
    stack.setCurrentComposite(.{ .alpha = 0.5, .operation = .source_over });
    stack.appendRect(.{ .x = 0, .y = 0, .width = 4, .height = 4, .rgba = blue });

    const blended = paintStackPixelAt(&stack, 1, 1, 0);
    try testing.expect(blended.r >= 120 and blended.r <= 135);
    try testing.expectEqual(@as(u8, 0), blended.g);
    try testing.expect(blended.b >= 120 and blended.b <= 135);
    try testing.expectEqual(@as(u8, 255), blended.a);
}

test "CanvasBitmap copy composite replaces destination" {
    var stack = PaintStack{};
    const red = color.RGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = color.RGBA{ .r = 0, .g = 0, .b = 255, .a = 255 };

    stack.appendRect(.{ .x = 0, .y = 0, .width = 4, .height = 4, .rgba = red });
    stack.setCurrentComposite(.{ .operation = .copy });
    stack.appendRect(.{ .x = 1, .y = 1, .width = 2, .height = 2, .rgba = blue });

    try testing.expectEqual(red, paintStackPixelAt(&stack, 0, 0, 0));
    try testing.expectEqual(blue, paintStackPixelAt(&stack, 1, 1, 0));

    stack.setCurrentComposite(.{ .alpha = 0.5, .operation = .copy });
    stack.appendRect(.{ .x = 2, .y = 2, .width = 1, .height = 1, .rgba = blue });
    const copied = paintStackPixelAt(&stack, 2, 2, 0);
    try testing.expectEqual(@as(u8, 0), copied.r);
    try testing.expectEqual(@as(u8, 0), copied.g);
    try testing.expectEqual(@as(u8, 255), copied.b);
    try testing.expect(copied.a >= 127 and copied.a <= 128);
}

test "CanvasBitmap clip masks future paint and restores clip state" {
    const red = color.RGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = color.RGBA{ .r = 0, .g = 0, .b = 255, .a = 255 };
    const green = color.RGBA{ .r = 0, .g = 255, .b = 0, .a = 255 };

    var stack = PaintStack{};
    stack.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = red });

    var clip = CanvasPath{};
    clip.rect(0, 0, 4, 4);
    stack.appendClip(clip, null);
    stack.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = blue });

    try testing.expectEqual(blue, paintStackPixelAt(&stack, 1, 1, 0));
    try testing.expectEqual(red, paintStackPixelAt(&stack, 6, 6, 0));

    const clipped_state = stack.currentClipBits();
    var narrower = CanvasPath{};
    narrower.rect(0, 0, 2, 2);
    stack.appendClip(narrower, null);
    stack.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = green });

    try testing.expectEqual(green, paintStackPixelAt(&stack, 1, 1, 0));
    try testing.expectEqual(blue, paintStackPixelAt(&stack, 3, 3, 0));
    try testing.expectEqual(red, paintStackPixelAt(&stack, 6, 6, 0));

    stack.setCurrentClipBits(clipped_state);
    stack.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = green });

    try testing.expectEqual(green, paintStackPixelAt(&stack, 3, 3, 0));
    try testing.expectEqual(red, paintStackPixelAt(&stack, 6, 6, 0));

    stack.setCurrentClipBits(0);
    stack.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = green });
    try testing.expectEqual(green, paintStackPixelAt(&stack, 6, 6, 0));
}

test "CanvasBitmap transform maps simple rect bounds" {
    var translated = Transform{};
    translated.translate(4, 3);
    const red = color.RGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const moved = translated.filledRect(.{ .x = 0, .y = 0, .width = 2, .height = 2, .rgba = red }).?;

    try testing.expectEqual(@as(f64, 4.0), moved.x);
    try testing.expectEqual(@as(f64, 3.0), moved.y);
    try testing.expectEqual(@as(f64, 2.0), moved.width);
    try testing.expectEqual(@as(f64, 2.0), moved.height);

    var scaled = Transform{};
    scaled.scale(2, 3);
    const expanded = scaled.rect(2, 4, 3, 2).?;
    try testing.expectEqual(@as(f64, 4.0), expanded.x);
    try testing.expectEqual(@as(f64, 12.0), expanded.y);
    try testing.expectEqual(@as(f64, 6.0), expanded.width);
    try testing.expectEqual(@as(f64, 6.0), expanded.height);
}

test "CanvasBitmap image patch copies dirty pixels and rejects overflowing bounds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const pixels = [_]u8{
        255, 0, 0,   255, 0,   255, 0,   255,
        0,   0, 255, 255, 255, 255, 255, 255,
    };
    const patch = (try imagePatch(allocator, 2, 2, pixels[0..], 4, 5, 1, 1, 1, 1)).?;

    try testing.expectEqual(@as(i64, 5), patch.x);
    try testing.expectEqual(@as(i64, 6), patch.y);
    try testing.expectEqual(@as(u32, 1), patch.width);
    try testing.expectEqual(@as(u32, 1), patch.height);
    try testing.expectEqual(color.RGBA{ .r = 255, .g = 255, .b = 255, .a = 255 }, patch.pixelAt(5, 6).?);
    try testing.expectEqual(@as(?color.RGBA, null), patch.pixelAt(4, 5));

    const max_i64 = @as(f64, @floatFromInt(std.math.maxInt(i64)));
    const min_i64 = @as(f64, @floatFromInt(std.math.minInt(i64)));
    try testing.expect(try imagePatch(allocator, 2, 2, pixels[0..], max_i64, 0, 1, 0, 1, 1) == null);
    try testing.expect(try imagePatch(allocator, 2, 2, pixels[0..], 0, 0, min_i64, 0, -1, 1) == null);
}

test "CanvasBitmap drawImage copies and scales source paint" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var source = PaintStack{};
    var dest = PaintStack{};
    const red = color.RGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = color.RGBA{ .r = 0, .g = 0, .b = 255, .a = 255 };

    source.appendRect(.{ .x = 0, .y = 0, .width = 1, .height = 2, .rgba = red });
    source.appendRect(.{ .x = 1, .y = 0, .width = 1, .height = 2, .rgba = blue });
    try dest.appendDrawImage(
        arena.allocator(),
        .{ .width = 2, .height = 2, .paint_stack = &source },
        .{},
        0,
        0,
        0,
        4,
        2,
        null,
        null,
        null,
        null,
    );

    try testing.expectEqual(red, paintStackPixelAt(&dest, 0, 0, 0));
    try testing.expectEqual(red, paintStackPixelAt(&dest, 1, 0, 0));
    try testing.expectEqual(blue, paintStackPixelAt(&dest, 2, 0, 0));
    try testing.expectEqual(blue, paintStackPixelAt(&dest, 3, 1, 0));
}

test "CanvasBitmap drawImage supports source and destination rectangles" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var source = PaintStack{};
    var dest = PaintStack{};
    const green = color.RGBA{ .r = 0, .g = 170, .b = 0, .a = 255 };

    source.appendRect(.{ .x = 2, .y = 1, .width = 2, .height = 2, .rgba = green });
    try dest.appendDrawImage(
        arena.allocator(),
        .{ .width = 6, .height = 6, .paint_stack = &source },
        .{},
        0,
        2,
        1,
        2,
        2,
        5,
        6,
        2,
        2,
    );

    try testing.expectEqual(green, paintStackPixelAt(&dest, 5, 6, 0));
    try testing.expectEqual(green, paintStackPixelAt(&dest, 6, 7, 0));
    try testing.expectEqual(color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 }, paintStackPixelAt(&dest, 4, 6, 0));
}
