const std = @import("std");
const js = @import("../../../js/js.zig");
const Frame = @import("../../../Frame.zig");
const Node = @import("../../Node.zig");
const Element = @import("../../Element.zig");
const HtmlElement = @import("../Html.zig");
const CanvasBitmap = @import("../../canvas/CanvasBitmap.zig");
const color = @import("../../../color.zig");

const Image = @This();
_proto: *HtmlElement,
_current_src: []const u8 = "",
_request_pending: bool = false,
_request_succeeded: bool = false,
_natural_width: u32 = 0,
_natural_height: u32 = 0,
_pixels: ?[]const u8 = null,

pub fn constructor(w_: ?u32, h_: ?u32, frame: *Frame) !*Image {
    const node = try Frame.node_factory.createElementNS(frame, .html, "img", null);
    const el = node.as(Element);

    if (w_) |w| blk: {
        const w_string = std.fmt.bufPrint(&frame.buf, "{d}", .{w}) catch break :blk;
        try el.setAttributeSafe(comptime .wrap("width"), .wrap(w_string), frame);
    }
    if (h_) |h| blk: {
        const h_string = std.fmt.bufPrint(&frame.buf, "{d}", .{h}) catch break :blk;
        try el.setAttributeSafe(comptime .wrap("height"), .wrap(h_string), frame);
    }
    return el.as(Image);
}

pub fn asElement(self: *Image) *Element {
    return self._proto._proto;
}
pub fn asConstElement(self: *const Image) *const Element {
    return self._proto._proto;
}
pub fn asNode(self: *Image) *Node {
    return self.asElement().asNode();
}

pub fn getSrc(self: *const Image, frame: *Frame) ![]const u8 {
    const element = self.asConstElement();
    const src = element.getAttributeSafe(comptime .wrap("src")) orelse return "";
    if (src.len == 0) {
        return "";
    }
    return element.asConstNode().resolveURL(src, frame, .{});
}

pub fn setSrc(self: *Image, value: []const u8, frame: *Frame) !void {
    const element = self.asElement();
    try element.setAttributeSafe(comptime .wrap("src"), .wrap(value), frame);
    // No need to check if `Image` is connected to DOM; this is a special case.
    return self.imageAddedCallback(frame);
}

pub fn getAlt(self: *const Image) []const u8 {
    return self.asConstElement().getAttributeSafe(comptime .wrap("alt")) orelse "";
}

pub fn setAlt(self: *Image, value: []const u8, frame: *Frame) !void {
    try self.asElement().setAttributeSafe(comptime .wrap("alt"), .wrap(value), frame);
}

pub fn getWidth(self: *const Image) u32 {
    const attr = self.asConstElement().getAttributeSafe(comptime .wrap("width")) orelse return 0;
    return std.fmt.parseUnsigned(u32, attr, 10) catch 0;
}

pub fn setWidth(self: *Image, value: u32, frame: *Frame) !void {
    const str = try std.fmt.allocPrint(frame.call_arena, "{d}", .{value});
    try self.asElement().setAttributeSafe(comptime .wrap("width"), .wrap(str), frame);
}

pub fn getHeight(self: *const Image) u32 {
    const attr = self.asConstElement().getAttributeSafe(comptime .wrap("height")) orelse return 0;
    return std.fmt.parseUnsigned(u32, attr, 10) catch 0;
}

pub fn setHeight(self: *Image, value: u32, frame: *Frame) !void {
    const str = try std.fmt.allocPrint(frame.call_arena, "{d}", .{value});
    try self.asElement().setAttributeSafe(comptime .wrap("height"), .wrap(str), frame);
}

pub fn getCrossOrigin(self: *const Image) ?[]const u8 {
    return self.asConstElement().getAttributeSafe(comptime .wrap("crossorigin"));
}

pub fn setCrossOrigin(self: *Image, value: ?[]const u8, frame: *Frame) !void {
    if (value) |v| {
        return self.asElement().setAttributeSafe(comptime .wrap("crossorigin"), .wrap(v), frame);
    }
    return self.asElement().removeAttribute(comptime .wrap("crossorigin"), frame);
}

pub fn getLoading(self: *const Image) []const u8 {
    return self.asConstElement().getAttributeSafe(comptime .wrap("loading")) orelse "eager";
}

pub fn setLoading(self: *Image, value: []const u8, frame: *Frame) !void {
    try self.asElement().setAttributeSafe(comptime .wrap("loading"), .wrap(value), frame);
}

pub fn getNaturalWidth(self: *const Image) u32 {
    return self._natural_width;
}

pub fn getNaturalHeight(self: *const Image) u32 {
    return self._natural_height;
}

pub fn getComplete(self: *const Image) bool {
    return !self._request_pending;
}

/// Used by `CanvasRenderingContext2D.drawImage` / `OffscreenCanvasRenderingContext2D.drawImage`
/// to treat this element as a valid `CanvasImageSource`, mirroring `Canvas.canvasSourceBitmap`.
pub fn imageSourceBitmap(self: *const Image) ?CanvasBitmap.SourceBitmap {
    if (self._natural_width == 0 or self._natural_height == 0) return null;
    return .{
        .width = self._natural_width,
        .height = self._natural_height,
        .static_pixels = self._pixels,
    };
}

pub fn beginImageRequest(self: *Image, frame: *Frame, resolved: []const u8) !bool {
    if (std.mem.eql(u8, self._current_src, resolved) and
        (self._request_pending or self._request_succeeded))
    {
        return false;
    }

    self._current_src = try frame.arena.dupe(u8, resolved);
    self._request_pending = true;
    self._request_succeeded = false;
    self._natural_width = 0;
    self._natural_height = 0;
    self._pixels = null;
    return true;
}

pub fn imageRequestSucceeded(self: *Image, frame: *Frame, body: []const u8) void {
    self._request_pending = false;
    self._request_succeeded = true;
    if (parseImageDimensions(body)) |dimensions| {
        self._natural_width = dimensions.width;
        self._natural_height = dimensions.height;
        self._pixels = decodePngPixels(frame.arena, body);
    }
}

pub fn imageRequestFailed(self: *Image) void {
    self._request_pending = false;
    self._request_succeeded = false;
    self._natural_width = 0;
    self._natural_height = 0;
    self._pixels = null;
}

fn clearImageRequest(self: *Image) void {
    self._current_src = "";
    self._request_pending = false;
    self._request_succeeded = false;
    self._natural_width = 0;
    self._natural_height = 0;
    self._pixels = null;
}

/// Used in `Page.nodeIsReady`.
pub fn imageAddedCallback(self: *Image, frame: *Frame) !void {
    const owner = self.asNode().ownerFrame(frame);
    // if we're planning on navigating to another frame, don't trigger load event.
    if (owner.isGoingAway()) {
        return;
    }

    const element = self.asElement();
    // Exit if src not set.
    const src = element.getAttributeSafe(comptime .wrap("src")) orelse {
        self.clearImageRequest();
        return;
    };
    if (src.len == 0) {
        self.clearImageRequest();
        return;
    }

    try owner.loadImage(self, src);
}

const ImageDimensions = struct {
    width: u32,
    height: u32,
};

fn parseImageDimensions(bytes: []const u8) ?ImageDimensions {
    return parsePngDimensions(bytes) orelse
        parseGifDimensions(bytes) orelse
        parseJpegDimensions(bytes) orelse
        parseWebpDimensions(bytes);
}

fn parsePngDimensions(bytes: []const u8) ?ImageDimensions {
    const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    if (bytes.len < 24 or !std.mem.eql(u8, bytes[0..8], &png_signature)) return null;
    if (!std.mem.eql(u8, bytes[12..16], "IHDR")) return null;
    return .{
        .width = std.mem.readInt(u32, bytes[16..20], .big),
        .height = std.mem.readInt(u32, bytes[20..24], .big),
    };
}

fn parseGifDimensions(bytes: []const u8) ?ImageDimensions {
    if (bytes.len < 10) return null;
    if (!std.mem.eql(u8, bytes[0..6], "GIF87a") and !std.mem.eql(u8, bytes[0..6], "GIF89a")) return null;
    return .{
        .width = std.mem.readInt(u16, bytes[6..8], .little),
        .height = std.mem.readInt(u16, bytes[8..10], .little),
    };
}

fn parseJpegDimensions(bytes: []const u8) ?ImageDimensions {
    if (bytes.len < 4 or bytes[0] != 0xff or bytes[1] != 0xd8) return null;

    var pos: usize = 2;
    while (pos + 4 <= bytes.len) {
        if (bytes[pos] != 0xff) return null;
        while (pos < bytes.len and bytes[pos] == 0xff) : (pos += 1) {}
        if (pos >= bytes.len) return null;

        const marker = bytes[pos];
        pos += 1;
        if (marker == 0xd9 or marker == 0xda) return null;
        if (marker >= 0xd0 and marker <= 0xd7) continue;
        if (pos + 2 > bytes.len) return null;

        const segment_len = std.mem.readInt(u16, bytes[pos..][0..2], .big);
        if (segment_len < 2 or pos + segment_len > bytes.len) return null;

        if ((marker >= 0xc0 and marker <= 0xc3) or
            (marker >= 0xc5 and marker <= 0xc7) or
            (marker >= 0xc9 and marker <= 0xcb) or
            (marker >= 0xcd and marker <= 0xcf))
        {
            if (segment_len < 7) return null;
            return .{
                .height = std.mem.readInt(u16, bytes[pos + 3 ..][0..2], .big),
                .width = std.mem.readInt(u16, bytes[pos + 5 ..][0..2], .big),
            };
        }

        pos += segment_len;
    }
    return null;
}

fn parseWebpDimensions(bytes: []const u8) ?ImageDimensions {
    if (bytes.len < 30) return null;
    if (!std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WEBP")) return null;

    const kind = bytes[12..16];
    if (std.mem.eql(u8, kind, "VP8X")) {
        return .{
            .width = read24Le(bytes[24..27]) + 1,
            .height = read24Le(bytes[27..30]) + 1,
        };
    }
    if (std.mem.eql(u8, kind, "VP8L") and bytes[20] == 0x2f) {
        const bits = std.mem.readInt(u32, bytes[21..25], .little);
        return .{
            .width = (bits & 0x3fff) + 1,
            .height = ((bits >> 14) & 0x3fff) + 1,
        };
    }
    if (std.mem.eql(u8, kind, "VP8 ") and std.mem.eql(u8, bytes[23..26], &[_]u8{ 0x9d, 0x01, 0x2a })) {
        return .{
            .width = std.mem.readInt(u16, bytes[26..28], .little) & 0x3fff,
            .height = std.mem.readInt(u16, bytes[28..30], .little) & 0x3fff,
        };
    }
    return null;
}

fn read24Le(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16);
}

const max_decoded_pixel_bytes = 4 * 1024 * 1024;

/// Decodes a PNG into a flat RGBA8 buffer, allocated from `allocator` (the
/// frame's long-lived arena, so the result outlives the fetch's scratch arena).
/// Fully infallible by design: any unsupported feature (16-bit depth,
/// interlacing, an exotic color type) or malformed input (bad signature, CRC
/// mismatch, truncated chunk, corrupt zlib stream) degrades to `null`, mirroring
/// `parseImageDimensions`'s existing graceful-degradation contract. Supports
/// color types 0/2/3/4/6 at 8-bit depth, non-interlaced only.
fn decodePngPixels(allocator: std.mem.Allocator, bytes: []const u8) ?[]const u8 {
    const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], &png_signature)) return null;

    var width: u32 = 0;
    var height: u32 = 0;
    var color_type: u8 = 0;
    var seen_ihdr = false;
    var palette: ?[]const u8 = null;
    var trns: ?[]const u8 = null;

    var idat_writer: std.Io.Writer.Allocating = .init(allocator);
    defer idat_writer.deinit();

    var pos: usize = 8;
    while (pos + 8 <= bytes.len) {
        const chunk_len: usize = std.mem.readInt(u32, bytes[pos..][0..4], .big);
        const chunk_type = bytes[pos + 4 ..][0..4];
        const data_start = pos + 8;
        if (chunk_len > bytes.len or data_start + chunk_len + 4 > bytes.len) return null;
        const data = bytes[data_start..][0..chunk_len];
        const crc_start = data_start + chunk_len;
        const stored_crc = std.mem.readInt(u32, bytes[crc_start..][0..4], .big);

        var crc = std.hash.Crc32.init();
        crc.update(chunk_type);
        crc.update(data);
        if (crc.final() != stored_crc) return null;

        if (std.mem.eql(u8, chunk_type, "IHDR")) {
            if (chunk_len != 13) return null;
            width = std.mem.readInt(u32, data[0..4], .big);
            height = std.mem.readInt(u32, data[4..8], .big);
            const bit_depth = data[8];
            color_type = data[9];
            const interlace = data[12];
            if (bit_depth != 8 or interlace != 0) return null;
            seen_ihdr = true;
        } else if (std.mem.eql(u8, chunk_type, "PLTE")) {
            palette = data;
        } else if (std.mem.eql(u8, chunk_type, "tRNS")) {
            trns = data;
        } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
            idat_writer.writer.writeAll(data) catch return null;
        } else if (std.mem.eql(u8, chunk_type, "IEND")) {
            break;
        }

        pos = crc_start + 4;
    }

    if (!seen_ihdr or width == 0 or height == 0) return null;
    const channels: u32 = switch (color_type) {
        0 => 1,
        2 => 3,
        3 => 1,
        4 => 2,
        6 => 4,
        else => return null,
    };
    if (color_type == 3 and palette == null) return null;

    const row_len = std.math.mul(u64, width, channels) catch return null;
    const raw_len_u64 = std.math.mul(u64, row_len + 1, height) catch return null;
    if (raw_len_u64 > max_decoded_pixel_bytes) return null;
    const raw_len: usize = @intCast(raw_len_u64);

    const out_len_u64 = std.math.mul(u64, @as(u64, width) * 4, height) catch return null;
    if (out_len_u64 > max_decoded_pixel_bytes) return null;
    const out_len: usize = @intCast(out_len_u64);

    const idat_bytes = idat_writer.written();
    if (idat_bytes.len == 0) return null;

    var in: std.Io.Reader = .fixed(idat_bytes);
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var decompress: std.compress.flate.Decompress = .init(&in, .zlib, &.{});
    _ = decompress.reader.streamRemaining(&aw.writer) catch return null;
    const raw = aw.written();
    if (raw.len != raw_len) return null;

    const out = allocator.alloc(u8, out_len) catch return null;
    const stride = @as(usize, width) * channels;
    const bpp = channels;
    var prev_row: []const u8 = &.{};
    var row_pos: usize = 0;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const filter_type = raw[row_pos];
        const filtered = raw[row_pos + 1 ..][0..stride];
        const row_buf = allocator.alloc(u8, stride) catch return null;
        defilterRow(filter_type, filtered, prev_row, bpp, row_buf) catch return null;

        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const src = row_buf[x * channels ..][0..channels];
            const dst = out[(y * width + x) * 4 ..][0..4];
            switch (color_type) {
                0 => {
                    dst[0] = src[0];
                    dst[1] = src[0];
                    dst[2] = src[0];
                    dst[3] = 255;
                },
                2 => {
                    dst[0] = src[0];
                    dst[1] = src[1];
                    dst[2] = src[2];
                    dst[3] = 255;
                },
                3 => {
                    const idx = src[0];
                    const plte = palette.?;
                    const pidx = @as(usize, idx) * 3;
                    if (pidx + 3 > plte.len) return null;
                    dst[0] = plte[pidx];
                    dst[1] = plte[pidx + 1];
                    dst[2] = plte[pidx + 2];
                    dst[3] = if (trns) |t| (if (idx < t.len) t[idx] else 255) else 255;
                },
                4 => {
                    dst[0] = src[0];
                    dst[1] = src[0];
                    dst[2] = src[0];
                    dst[3] = src[1];
                },
                6 => {
                    dst[0] = src[0];
                    dst[1] = src[1];
                    dst[2] = src[2];
                    dst[3] = src[3];
                },
                else => unreachable,
            }
        }

        prev_row = row_buf;
        row_pos += 1 + stride;
    }

    return out;
}

fn defilterRow(filter_type: u8, filtered: []const u8, prev: []const u8, bpp: u32, out: []u8) !void {
    var i: usize = 0;
    while (i < filtered.len) : (i += 1) {
        const x = filtered[i];
        const a: u8 = if (i >= bpp) out[i - bpp] else 0;
        const b: u8 = if (i < prev.len) prev[i] else 0;
        const c: u8 = if (i >= bpp and i - bpp < prev.len) prev[i - bpp] else 0;
        out[i] = switch (filter_type) {
            0 => x,
            1 => x +% a,
            2 => x +% b,
            3 => x +% @as(u8, @intCast((@as(u16, a) + @as(u16, b)) / 2)),
            4 => x +% paethPredictor(a, b, c),
            else => return error.InvalidFilterType,
        };
    }
}

fn paethPredictor(a: u8, b: u8, c: u8) u8 {
    const p: i32 = @as(i32, a) + @as(i32, b) - @as(i32, c);
    const pa = @abs(p - @as(i32, a));
    const pb = @abs(p - @as(i32, b));
    const pc = @abs(p - @as(i32, c));
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Image);

    pub const Meta = struct {
        pub const name = "HTMLImageElement";
        pub const constructor_alias = "Image";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(Image.constructor, .{});
    pub const src = bridge.accessor(Image.getSrc, Image.setSrc, .{ .ce_reactions = true });
    pub const currentSrc = bridge.accessor(Image.getSrc, null, .{});
    pub const alt = bridge.accessor(Image.getAlt, Image.setAlt, .{ .ce_reactions = true });
    pub const width = bridge.accessor(Image.getWidth, Image.setWidth, .{ .ce_reactions = true });
    pub const height = bridge.accessor(Image.getHeight, Image.setHeight, .{ .ce_reactions = true });
    pub const crossOrigin = bridge.accessor(Image.getCrossOrigin, Image.setCrossOrigin, .{ .ce_reactions = true });
    pub const loading = bridge.accessor(Image.getLoading, Image.setLoading, .{ .ce_reactions = true });
    pub const naturalWidth = bridge.accessor(Image.getNaturalWidth, null, .{});
    pub const naturalHeight = bridge.accessor(Image.getNaturalHeight, null, .{});
    pub const complete = bridge.accessor(Image.getComplete, null, .{});
};

// Parser-created <img> elements are void (no closing tag) so they never
// reach `Frame.nodeComplete`. Fire `imageAddedCallback` at element-create
// time instead, mirroring `Link.Build.created`.
pub const Build = struct {
    pub fn created(node: *Node, frame: *Frame) !void {
        const self = node.as(Image);
        return self.imageAddedCallback(frame);
    }
};

const testing = @import("../../../../testing.zig");
test "WebApi: HTML.Image" {
    try testing.htmlRunner("element/html/image.html", .{});
}

test "WebApi: HTML.Image dimensions from image headers" {
    try testing.expectEqual(ImageDimensions{ .width = 2, .height = 3 }, parseImageDimensions(&.{
        0x89, 'P',  'N',  'G',  '\r', '\n', 0x1a, '\n',
        0x00, 0x00, 0x00, 0x0d, 'I',  'H',  'D',  'R',
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03,
    }).?);
    try testing.expectEqual(ImageDimensions{ .width = 4, .height = 5 }, parseImageDimensions("GIF89a\x04\x00\x05\x00").?);
}

// The 14 RGB swatches from the compatibility test site's canvas round-trip
// fidelity check: fillRect -> toDataURL (PNG encode) -> <img> decode ->
// drawImage -> getImageData, requiring all 25 pixels of each l=5,v=5 swatch
// block to come back self-consistent -- i.e. matching what a direct
// (non-round-tripped) read of the source canvas reports at that same pixel,
// noise included. See CanvasBitmap.zig's `noisyChannel` / `Paint.noiseEligible`
// / `PaintStack.basePixelAt` for how the seeded anti-tracking noise is baked
// in exactly once, at vector-rasterization time, so it survives an
// encode/decode/composite round trip without being re-applied on readback.
const round_trip_swatches = [_][3]u8{
    .{ 255, 0, 0 },     .{ 0, 255, 0 },     .{ 0, 0, 255 },     .{ 255, 255, 0 },
    .{ 255, 0, 255 },   .{ 0, 255, 255 },   .{ 1, 1, 1 },       .{ 254, 254, 254 },
    .{ 0, 0, 0 },       .{ 51, 51, 51 },    .{ 102, 102, 102 }, .{ 153, 153, 153 },
    .{ 204, 204, 204 }, .{ 255, 255, 255 },
};

/// Runs the exact algorithm the fingerprint-compat site uses (l=5, v=5),
/// through the real production code paths: `Transform.filledRect` +
/// `PaintStack.appendRect` (fillRect), `CanvasBitmap.png` (toDataURL's PNG
/// encoder), `decodePngPixels` (the <img> decoder), `PaintStack.appendDrawImage`
/// (drawImage's 1:1 blit/composite), and `paintStackPixelAt` (getImageData).
/// Returns, per swatch, how many of the 25 pixels came back *self-consistent*
/// with a direct (non-round-tripped) read of canvas1 at that same coordinate
/// -- not how many match the pre-noise input byte value, since a seeded
/// profile is expected to (and must, for the anti-tracking property to mean
/// anything) legitimately differ from the literal fillRect color.
fn runCanvasRoundTripFidelity(allocator: std.mem.Allocator, seed: u64) ![round_trip_swatches.len]u32 {
    const l: u32 = 5;
    const v: u32 = 5;
    const width = l * round_trip_swatches.len;
    const height = v;

    // canvas1: ctx.fillRect(l*idx, 0, l*(1+idx), v) for each swatch, in order.
    var stack1 = CanvasBitmap.PaintStack{};
    for (round_trip_swatches, 0..) |rgb, idx| {
        const hex = try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb[0], rgb[1], rgb[2] });
        const rgba = try color.RGBA.parse(hex); // fillStyle hex parsing (suspect #4)
        const rect = (CanvasBitmap.Transform{}).filledRect(.{
            .x = @floatFromInt(l * idx),
            .y = 0,
            .width = @floatFromInt(l * (1 + idx)),
            .height = @floatFromInt(v),
            .rgba = rgba,
        }).?;
        stack1.appendRect(rect);
    }

    // toDataURL(): PNG-encode canvas1's raw pixels (noise, if any, is baked in here).
    const raw_len = CanvasBitmap.rawLen(width, height).?;
    const raw = try CanvasBitmap.rawPixelsForPaintStack(allocator, seed, width, height, raw_len, &stack1);
    const png_bytes = try CanvasBitmap.png(allocator, width, height, raw);

    // <img>.src = dataUrl; onload decodes the PNG (real decoder, not a re-derivation).
    const decoded = decodePngPixels(allocator, png_bytes) orelse return error.DecodeFailed;

    // canvas2.drawImage(img, 0, 0): 1:1 opaque blit via the real compositor.
    var stack2 = CanvasBitmap.PaintStack{};
    try stack2.appendDrawImage(
        allocator,
        .{ .width = width, .height = height, .static_pixels = decoded },
        .{},
        seed,
        0,
        0,
        null,
        null,
        null,
        null,
        null,
        null,
    );

    // getImageData(l*idx, 0, l, v) per swatch: compare the round-tripped pixel
    // against a DIRECT (non-round-tripped) read of canvas1's own paint stack
    // at the same coordinate. That is the actual self-consistency invariant --
    // canvas1's own noised output, reproduced faithfully through the PNG
    // encode/decode/composite hop -- not equality with the pre-noise input.
    var counts: [round_trip_swatches.len]u32 = undefined;
    for (round_trip_swatches, 0..) |_, idx| {
        var matches: u32 = 0;
        var y: u32 = 0;
        while (y < v) : (y += 1) {
            var x: u32 = 0;
            while (x < l) : (x += 1) {
                const px_x: i64 = @intCast(l * idx + x);
                const px_y: i64 = @intCast(y);
                const direct = CanvasBitmap.paintStackPixelAt(&stack1, px_x, px_y, seed);
                const round_tripped = CanvasBitmap.paintStackPixelAt(&stack2, px_x, px_y, seed);
                if (std.meta.eql(direct, round_tripped)) matches += 1;
            }
        }
        counts[idx] = matches;
    }
    return counts;
}

test "WebApi: HTML.Image canvas round-trip fidelity is byte-exact with no seeded canvas noise" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // seed=0 mirrors the default (no chimera canvas profile authority loaded),
    // which is what `make test`'s HTML/CDP harness runs under. This isolates
    // fillRect/fillStyle parsing, the PNG encoder, the PNG decoder, and
    // drawImage's compositor from the seeded-noise stealth surface below:
    // every one of the 4 "likely suspect" stages is clean at seed=0.
    const counts = try runCanvasRoundTripFidelity(arena.allocator(), 0);
    const expected_all_25 = [_]u32{25} ** round_trip_swatches.len;
    try testing.expectEqualSlices(u32, &expected_all_25, &counts);
}

test "WebApi: HTML.Image canvas round-trip fidelity stays self-consistent under seeded canvas noise" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A nonzero seed reproduces `profile.canvas.enabled=true` in
    // CanvasRenderingContext2D.canvasSeed / Canvas.canvasSeed. Previously,
    // every read of a canvas -- including a `.image` op holding pixel bytes
    // already noised once by an earlier materialization -- ran back through
    // CanvasBitmap.paintStackPixelAt's blanket per-read noise, perturbing
    // already-noised bytes a second time. That broke this exact round trip:
    // fillRect (fresh vector content, noised once at toDataURL's PNG raster)
    // -> PNG decode -> drawImage (copies the already-noised bytes verbatim)
    // -> getImageData (used to re-noise them on top).
    //
    // The fix (CanvasBitmap.zig: `Paint.noiseEligible`, `basePixelAt`) bakes
    // the -1/0/+1 `noisyChannel` perturbation in once, at the point a *vector*
    // op (rect/path/text/stroke) is actually sampled/rasterized, and never
    // applies it to `.image` ops (already-materialized/copied pixel data --
    // from `drawImage` or `putImageData`). So the PNG-encoded bytes, the
    // decoded `.image` patch copied into canvas2, and canvas2's own
    // `getImageData` readback all carry the *same* single noised value that a
    // direct read of canvas1 would report at that coordinate: every swatch
    // pixel is self-consistent, even though the seed is active and the
    // pixel's color legitimately differs from the pre-noise fillRect input
    // (that divergence from the input is the anti-tracking property working;
    // see the differentiation tests below).
    const seed: u64 = 0xC0FFEE_1234_5678;
    const counts = try runCanvasRoundTripFidelity(arena.allocator(), seed);

    const expected_all_25 = [_]u32{25} ** round_trip_swatches.len;
    try testing.expectEqualSlices(u32, &expected_all_25, &counts);
}

test "WebApi: HTML.Image canvas noise still differentiates seeds for identical drawn content" {
    // Property (a): different profiles/seeds must still produce different
    // canvas output for byte-identical drawn content -- the anti-tracking
    // property the noise exists for must survive the self-consistency fix.
    var stack = CanvasBitmap.PaintStack{};
    stack.appendRect(.{ .x = 0, .y = 0, .width = 20, .height = 20, .rgba = try color.RGBA.parse("#336699") });

    const seed_a: u64 = 0xC0FFEE_1234_5678;
    const seed_b: u64 = 0xFACADE_9876_5432;

    var differing: u32 = 0;
    var y: i64 = 0;
    while (y < 20) : (y += 1) {
        var x: i64 = 0;
        while (x < 20) : (x += 1) {
            const a = CanvasBitmap.paintStackPixelAt(&stack, x, y, seed_a);
            const b = CanvasBitmap.paintStackPixelAt(&stack, x, y, seed_b);
            if (!std.meta.eql(a, b)) differing += 1;
        }
    }
    // Two independent seeds should diverge across most of a 400-pixel fill;
    // a noise formula that accidentally collapsed to a no-op (or to the same
    // output regardless of seed) would fail this outright.
    try testing.expect(differing > 200);
}

test "WebApi: HTML.Image canvas noise still differentiates distinct drawn content" {
    // Property (b): distinct actual content must still produce visibly
    // different output under the same seed -- noise must not accidentally
    // collapse different drawings to indistinguishable pixels.
    var stack_red = CanvasBitmap.PaintStack{};
    var stack_blue = CanvasBitmap.PaintStack{};
    stack_red.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = try color.RGBA.parse("#ff0000") });
    stack_blue.appendRect(.{ .x = 0, .y = 0, .width = 10, .height = 10, .rgba = try color.RGBA.parse("#0000ff") });

    const seed: u64 = 0xC0FFEE_1234_5678;
    var differing: u32 = 0;
    var y: i64 = 0;
    while (y < 10) : (y += 1) {
        var x: i64 = 0;
        while (x < 10) : (x += 1) {
            const red_px = CanvasBitmap.paintStackPixelAt(&stack_red, x, y, seed);
            const blue_px = CanvasBitmap.paintStackPixelAt(&stack_blue, x, y, seed);
            if (!std.meta.eql(red_px, blue_px)) differing += 1;
        }
    }
    try testing.expectEqual(@as(u32, 100), differing);
}
