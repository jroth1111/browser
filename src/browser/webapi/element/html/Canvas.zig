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

const CanvasRenderingContext2D = @import("../../canvas/CanvasRenderingContext2D.zig");
const WebGLRenderingContext = @import("../../canvas/WebGLRenderingContext.zig");
const OffscreenCanvas = @import("../../canvas/OffscreenCanvas.zig");
const Seeds = @import("../../../../chimera/Seeds.zig");

const Execution = js.Execution;
const max_canvas_png_raw_bytes = 4 * 1024 * 1024;

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

        // We only stub a tiny slice of the WebGL API (getParameter,
        // getExtension, getSupportedExtensions). Real WebGL consumers like
        // Three.js immediately call createTexture/createBuffer/etc. and
        // throw `TypeError: e.createTexture is not a function`. Pretending
        // WebGL works until the first non-stubbed call is the worst of both
        // worlds: pages that have an error boundary above the WebGL widget
        // catch the throw, reset, re-render, and loop forever.
        // Spec-correct signal for "no WebGL" is null, so apps that check
        // (Three.js does) can degrade gracefully.
        if (std.mem.eql(u8, context_type, "webgl") or std.mem.eql(u8, context_type, "experimental-webgl")) {
            return null;
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

    const seed = canvasSeed(frame);
    const width = self.getWidth();
    const height = self.getHeight();
    if (width == 0 or height == 0) return "data:,";

    const raw_len = canvasRawLen(width, height) orelse return "data:,";
    if (raw_len > max_canvas_png_raw_bytes) return "data:,";
    const raw = try canvasRawPixels(frame.call_arena, seed, width, height, raw_len);
    const png = try canvasPng(frame.call_arena, width, height, raw);

    const encoder = std.base64.standard.Encoder;
    const prefix = "data:image/png;base64,";
    const encoded_size = encoder.calcSize(png.len);
    const out = try frame.call_arena.alloc(u8, prefix.len + encoded_size);
    @memcpy(out[0..prefix.len], prefix);
    _ = encoder.encode(out[prefix.len..], png);
    return out;
}

fn canvasSeed(frame: *Frame) u64 {
    const authority = frame._session.browser.http_client.network.config.chimeraAuthority() orelse return 0;
    if (!authority.profile.canvas.enabled) return 0;
    return Seeds.surfaceSeed(&authority.profile, .canvas);
}

fn canvasRawLen(width: u32, height: u32) ?usize {
    const row_len = std.math.mul(u64, width, 4) catch return null;
    const raw_len = std.math.mul(u64, row_len + 1, height) catch return null;
    if (raw_len > std.math.maxInt(usize)) return null;
    return @intCast(raw_len);
}

fn canvasRawPixels(allocator: std.mem.Allocator, seed: u64, width: u32, height: u32, raw_len: usize) ![]const u8 {
    const out = try allocator.alloc(u8, raw_len);
    var pos: usize = 0;
    for (0..height) |y| {
        out[pos] = 0;
        pos += 1;
        for (0..width) |x| {
            const mixed = Seeds.mix(seed, (@as(u64, @intCast(y)) << 32) | @as(u64, @intCast(x)));
            out[pos + 0] = @truncate(mixed >> 56);
            out[pos + 1] = @truncate(mixed >> 48);
            out[pos + 2] = @truncate(mixed >> 40);
            out[pos + 3] = 255;
            pos += 4;
        }
    }
    return out;
}

fn canvasPng(allocator: std.mem.Allocator, width: u32, height: u32, raw: []const u8) ![]const u8 {
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

const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };

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
};
