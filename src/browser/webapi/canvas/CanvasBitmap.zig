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
    path: FilledPath,

    fn pixelAt(self: *const Paint, x: i64, y: i64) ?color.RGBA {
        return switch (self.*) {
            .rect => |rect| if (rect.contains(x, y)) rect.rgba else null,
            .path => |path| if (path.contains(x, y)) path.rgba else null,
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

    pub fn appendText(self: *PaintStack, text: []const u8, x: f64, y: f64, max_width: ?f64, rgba: color.RGBA, font: []const u8) void {
        if (textFilledRect(text, x, y, max_width, rgba, font)) |rect| {
            self.appendRect(rect);
        }
    }

    pub fn appendPath(self: *PaintStack, path: CanvasPath, rgba: color.RGBA, maybe_fill_rule: ?[]const u8) void {
        if (path.isEmpty()) return;
        self.append(.{ .path = FilledPath.init(path, rgba, maybe_fill_rule) });
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

fn finite(value: f64) bool {
    return !std.math.isNan(value) and !std.math.isInf(value);
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
