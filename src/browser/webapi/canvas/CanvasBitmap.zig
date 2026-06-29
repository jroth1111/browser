const std = @import("std");

const color = @import("../../color.zig");
const Seeds = @import("../../../chimera/Seeds.zig");

pub const max_png_raw_bytes = 4 * 1024 * 1024;
pub const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };

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

pub fn rawLen(width: u32, height: u32) ?usize {
    const row_len = std.math.mul(u64, width, 4) catch return null;
    const raw_len = std.math.mul(u64, row_len + 1, height) catch return null;
    if (raw_len > std.math.maxInt(usize)) return null;
    return @intCast(raw_len);
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
    const out = try allocator.alloc(u8, raw_len);
    var pos: usize = 0;
    for (0..height) |y| {
        out[pos] = 0;
        pos += 1;
        for (0..width) |x| {
            const rgba = pixelAt(filled_rect, @as(i64, @intCast(x)), @as(i64, @intCast(y)), seed);
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
    var rgba = basePixelAt(filled_rect, x, y);
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

fn basePixelAt(filled_rect: ?FilledRect, x: i64, y: i64) color.RGBA {
    if (filled_rect) |rect| {
        if (rect.contains(x, y)) return rect.rgba;
    }
    return .{ .r = 0, .g = 0, .b = 0, .a = 0 };
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
