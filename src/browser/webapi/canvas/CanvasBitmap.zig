const std = @import("std");

const color = @import("../../color.zig");
const Seeds = @import("../../../chimera/Seeds.zig");
const CanvasPath = @import("CanvasPath.zig");

pub const max_png_raw_bytes = 4 * 1024 * 1024;
pub const max_paint_ops = 32;
pub const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
pub const default_font = "10px sans-serif";

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

pub const Paint = union(enum) {
    rect: FilledRect,
    clear_rect: ClearedRect,
    stroke_rect: StrokedRect,
    path: FilledPath,
    image: ImagePatch,

    fn pixelAt(self: *const Paint, x: i64, y: i64) ?color.RGBA {
        return switch (self.*) {
            .rect => |rect| if (rect.contains(x, y)) rect.rgba else null,
            .clear_rect => |rect| if (rect.contains(x, y)) color.RGBA{ .r = 0, .g = 0, .b = 0, .a = 0 } else null,
            .stroke_rect => |rect| if (rect.contains(x, y)) rect.rgba else null,
            .path => |path| if (path.contains(x, y)) path.rgba else null,
            .image => |image| image.pixelAt(x, y),
        };
    }
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

pub const PaintStack = struct {
    ops: [max_paint_ops]Paint = undefined,
    count: usize = 0,

    pub fn clear(self: *PaintStack) void {
        self.count = 0;
    }

    pub fn appendRect(self: *PaintStack, rect: FilledRect) void {
        self.append(.{ .rect = rect });
    }

    pub fn appendClearRect(self: *PaintStack, x: f64, y: f64, width: f64, height: f64) void {
        if (ClearedRect.init(x, y, width, height)) |rect| {
            self.append(.{ .clear_rect = rect });
        }
    }

    pub fn appendStrokeRect(self: *PaintStack, x: f64, y: f64, width: f64, height: f64, line_width: f64, rgba: color.RGBA) void {
        if (StrokedRect.init(x, y, width, height, line_width, rgba)) |rect| {
            self.append(.{ .stroke_rect = rect });
        }
    }

    pub fn appendText(self: *PaintStack, text: []const u8, x: f64, y: f64, max_width: ?f64, rgba: color.RGBA, font: []const u8) void {
        if (textFilledRect(text, x, y, max_width, rgba, font)) |rect| {
            self.appendRect(rect);
        }
    }

    pub fn appendPath(self: *PaintStack, path: CanvasPath, rgba: color.RGBA, maybe_fill_rule: ?[]const u8) void {
        if (path.isEmpty()) return;
        self.append(.{ .path = FilledPath.init(path, rgba, maybe_fill_rule) });
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
        self.append(.{ .image = patch });
    }

    fn append(self: *PaintStack, paint: Paint) void {
        if (self.count < max_paint_ops) {
            self.ops[self.count] = paint;
            self.count += 1;
            return;
        }

        var i: usize = 1;
        while (i < max_paint_ops) : (i += 1) {
            self.ops[i - 1] = self.ops[i];
        }
        self.ops[max_paint_ops - 1] = paint;
    }

    fn basePixelAt(self: *const PaintStack, x: i64, y: i64) color.RGBA {
        var i = self.count;
        while (i > 0) {
            i -= 1;
            if (self.ops[i].pixelAt(x, y)) |rgba| return rgba;
        }
        return .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    }
};

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

pub fn textWidth(text: []const u8, font: []const u8) f64 {
    const font_size = fontPixelSize(font);
    var width: f64 = 0;
    for (text) |byte| {
        if ((byte & 0xC0) == 0x80) continue;
        const advance = switch (byte) {
            ' ', '\t', '\n', '\r' => 0.25,
            0x00...0x7f => 0.48,
            else => 0.8,
        };
        width += font_size * advance;
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
    if (value < @as(f64, @floatFromInt(std.math.minInt(i64)))) return null;
    if (value > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return null;
    return @intFromFloat(@trunc(value));
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
    var rgba = paint_stack.basePixelAt(x, y);
    if (seed != 0 and rgba.a != 0) {
        rgba.r = noisyChannel(rgba.r, seed, x, y, 0);
        rgba.g = noisyChannel(rgba.g, seed, x, y, 1);
        rgba.b = noisyChannel(rgba.b, seed, x, y, 2);
    }
    return rgba;
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
