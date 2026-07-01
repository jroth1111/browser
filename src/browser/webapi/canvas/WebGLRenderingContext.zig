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
const Frame = @import("../../Frame.zig");
const Profile = @import("../../../chimera/Profile.zig");

const texture_unit_count: usize = 32;
const texture_sample_texel_count: usize = 16;

pub fn registerTypes() []const type {
    return &.{
        WebGLRenderingContext,
        WebGLActiveInfo,
        WebGLBuffer,
        WebGLFramebuffer,
        WebGLProgram,
        WebGLRenderbuffer,
        WebGLShader,
        WebGLShaderPrecisionFormat,
        WebGLTexture,
        WebGLUniformLocation,
        // Extension types should be runtime generated. We might want
        // to revisit this.
        Extension.Type.WEBGL_debug_renderer_info,
        Extension.Type.WEBGL_lose_context,
    };
}

const WebGLRenderingContext = @This();

drawing_buffer_width: u32 = 300,
drawing_buffer_height: u32 = 150,
viewport_values: [4]i32 = .{ 0, 0, 300, 150 },
scissor_box_values: [4]i32 = .{ 0, 0, 300, 150 },
clear_color_values: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
clear_pixel_values: [4]u8 = .{ 0, 0, 0, 0 },
draw_pixel_values: [4]u8 = .{ 0, 0, 0, 0 },
has_drawn_pixels: bool = false,
bound_array_buffer: ?*WebGLBuffer = null,
bound_framebuffer: ?*WebGLFramebuffer = null,
texture_units_2d: [texture_unit_count]?*WebGLTexture = .{null} ** texture_unit_count,
active_texture_unit: usize = 0,
current_program: ?*WebGLProgram = null,
attrib0_array_enabled: bool = false,
attrib0_pointer_enabled: bool = false,
unmasked_vendor: []const u8 = chrome_unmasked_vendor,
unmasked_renderer: []const u8 = chrome_unmasked_renderer,

pub const DEPTH_BUFFER_BIT: u64 = 0x00000100;
pub const STENCIL_BUFFER_BIT: u64 = 0x00000400;
pub const COLOR_BUFFER_BIT: u64 = 0x00004000;
pub const POINTS: u64 = 0x0000;
pub const LINES: u64 = 0x0001;
pub const LINE_LOOP: u64 = 0x0002;
pub const LINE_STRIP: u64 = 0x0003;
pub const TRIANGLES: u64 = 0x0004;
pub const TRIANGLE_STRIP: u64 = 0x0005;
pub const TRIANGLE_FAN: u64 = 0x0006;
pub const ZERO: u64 = 0;
pub const ONE: u64 = 1;
pub const SRC_COLOR: u64 = 0x0300;
pub const ONE_MINUS_SRC_COLOR: u64 = 0x0301;
pub const SRC_ALPHA: u64 = 0x0302;
pub const ONE_MINUS_SRC_ALPHA: u64 = 0x0303;
pub const DST_ALPHA: u64 = 0x0304;
pub const ONE_MINUS_DST_ALPHA: u64 = 0x0305;
pub const DST_COLOR: u64 = 0x0306;
pub const ONE_MINUS_DST_COLOR: u64 = 0x0307;
pub const SRC_ALPHA_SATURATE: u64 = 0x0308;
pub const FUNC_ADD: u64 = 0x8006;
pub const BLEND_EQUATION: u64 = 0x8009;
pub const BLEND_EQUATION_RGB: u64 = 0x8009;
pub const BLEND_EQUATION_ALPHA: u64 = 0x883D;
pub const FUNC_SUBTRACT: u64 = 0x800A;
pub const FUNC_REVERSE_SUBTRACT: u64 = 0x800B;
pub const BLEND_DST_RGB: u64 = 0x80C8;
pub const BLEND_SRC_RGB: u64 = 0x80C9;
pub const BLEND_DST_ALPHA: u64 = 0x80CA;
pub const BLEND_SRC_ALPHA: u64 = 0x80CB;
pub const CONSTANT_COLOR: u64 = 0x8001;
pub const ONE_MINUS_CONSTANT_COLOR: u64 = 0x8002;
pub const CONSTANT_ALPHA: u64 = 0x8003;
pub const ONE_MINUS_CONSTANT_ALPHA: u64 = 0x8004;
pub const BLEND_COLOR: u64 = 0x8005;
pub const ARRAY_BUFFER: u64 = 0x8892;
pub const ELEMENT_ARRAY_BUFFER: u64 = 0x8893;
pub const ARRAY_BUFFER_BINDING: u64 = 0x8894;
pub const ELEMENT_ARRAY_BUFFER_BINDING: u64 = 0x8895;
pub const STREAM_DRAW: u64 = 0x88E0;
pub const STATIC_DRAW: u64 = 0x88E4;
pub const DYNAMIC_DRAW: u64 = 0x88E8;
pub const BUFFER_SIZE: u64 = 0x8764;
pub const BUFFER_USAGE: u64 = 0x8765;
pub const CURRENT_VERTEX_ATTRIB: u64 = 0x8626;
pub const FRONT: u64 = 0x0404;
pub const BACK: u64 = 0x0405;
pub const FRONT_AND_BACK: u64 = 0x0408;
pub const TEXTURE_2D: u64 = 0x0DE1;
pub const TEXTURE0: u64 = 0x84C0;
pub const TEXTURE1: u64 = 0x84C1;
pub const TEXTURE2: u64 = 0x84C2;
pub const TEXTURE3: u64 = 0x84C3;
pub const TEXTURE4: u64 = 0x84C4;
pub const TEXTURE5: u64 = 0x84C5;
pub const TEXTURE6: u64 = 0x84C6;
pub const TEXTURE7: u64 = 0x84C7;
pub const TEXTURE8: u64 = 0x84C8;
pub const TEXTURE9: u64 = 0x84C9;
pub const TEXTURE10: u64 = 0x84CA;
pub const TEXTURE11: u64 = 0x84CB;
pub const TEXTURE12: u64 = 0x84CC;
pub const TEXTURE13: u64 = 0x84CD;
pub const TEXTURE14: u64 = 0x84CE;
pub const TEXTURE15: u64 = 0x84CF;
pub const TEXTURE16: u64 = 0x84D0;
pub const TEXTURE17: u64 = 0x84D1;
pub const TEXTURE18: u64 = 0x84D2;
pub const TEXTURE19: u64 = 0x84D3;
pub const TEXTURE20: u64 = 0x84D4;
pub const TEXTURE21: u64 = 0x84D5;
pub const TEXTURE22: u64 = 0x84D6;
pub const TEXTURE23: u64 = 0x84D7;
pub const TEXTURE24: u64 = 0x84D8;
pub const TEXTURE25: u64 = 0x84D9;
pub const TEXTURE26: u64 = 0x84DA;
pub const TEXTURE27: u64 = 0x84DB;
pub const TEXTURE28: u64 = 0x84DC;
pub const TEXTURE29: u64 = 0x84DD;
pub const TEXTURE30: u64 = 0x84DE;
pub const TEXTURE31: u64 = 0x84DF;
pub const ACTIVE_TEXTURE: u64 = 0x84E0;
pub const TEXTURE_MAG_FILTER: u64 = 0x2800;
pub const TEXTURE_MIN_FILTER: u64 = 0x2801;
pub const TEXTURE_WRAP_S: u64 = 0x2802;
pub const TEXTURE_WRAP_T: u64 = 0x2803;
pub const NEAREST: u64 = 0x2600;
pub const LINEAR: u64 = 0x2601;
pub const CLAMP_TO_EDGE: u64 = 0x812F;
pub const CULL_FACE: u64 = 0x0B44;
pub const BLEND: u64 = 0x0BE2;
pub const DITHER: u64 = 0x0BD0;
pub const STENCIL_TEST: u64 = 0x0B90;
pub const DEPTH_TEST: u64 = 0x0B71;
pub const SCISSOR_TEST: u64 = 0x0C11;
pub const POLYGON_OFFSET_FILL: u64 = 0x8037;
pub const SAMPLE_ALPHA_TO_COVERAGE: u64 = 0x809E;
pub const SAMPLE_COVERAGE: u64 = 0x80A0;
pub const NO_ERROR: u64 = 0;
pub const INVALID_ENUM: u64 = 0x0500;
pub const INVALID_VALUE: u64 = 0x0501;
pub const INVALID_OPERATION: u64 = 0x0502;
pub const OUT_OF_MEMORY: u64 = 0x0505;
pub const CW: u64 = 0x0900;
pub const CCW: u64 = 0x0901;
pub const LINE_WIDTH: u64 = 0x0B21;
pub const ALIASED_POINT_SIZE_RANGE: u64 = 0x846D;
pub const ALIASED_LINE_WIDTH_RANGE: u64 = 0x846E;
pub const CULL_FACE_MODE: u64 = 0x0B45;
pub const FRONT_FACE: u64 = 0x0B46;
pub const DEPTH_RANGE: u64 = 0x0B70;
pub const DEPTH_WRITEMASK: u64 = 0x0B72;
pub const DEPTH_CLEAR_VALUE: u64 = 0x0B73;
pub const DEPTH_FUNC: u64 = 0x0B74;
pub const STENCIL_CLEAR_VALUE: u64 = 0x0B91;
pub const STENCIL_FUNC: u64 = 0x0B92;
pub const STENCIL_FAIL: u64 = 0x0B94;
pub const STENCIL_PASS_DEPTH_FAIL: u64 = 0x0B95;
pub const STENCIL_PASS_DEPTH_PASS: u64 = 0x0B96;
pub const STENCIL_REF: u64 = 0x0B97;
pub const STENCIL_VALUE_MASK: u64 = 0x0B93;
pub const STENCIL_WRITEMASK: u64 = 0x0B98;
pub const VIEWPORT: u64 = 0x0BA2;
pub const SCISSOR_BOX: u64 = 0x0C10;
pub const COLOR_CLEAR_VALUE: u64 = 0x0C22;
pub const COLOR_WRITEMASK: u64 = 0x0C23;
pub const UNPACK_ALIGNMENT: u64 = 0x0CF5;
pub const PACK_ALIGNMENT: u64 = 0x0D05;
pub const MAX_TEXTURE_SIZE: u64 = 0x0D33;
pub const MAX_CUBE_MAP_TEXTURE_SIZE: u64 = 0x851C;
pub const MAX_VIEWPORT_DIMS: u64 = 0x0D3A;
pub const SUBPIXEL_BITS: u64 = 0x0D50;
pub const RED_BITS: u64 = 0x0D52;
pub const GREEN_BITS: u64 = 0x0D53;
pub const BLUE_BITS: u64 = 0x0D54;
pub const ALPHA_BITS: u64 = 0x0D55;
pub const DEPTH_BITS: u64 = 0x0D56;
pub const STENCIL_BITS: u64 = 0x0D57;
pub const POLYGON_OFFSET_UNITS: u64 = 0x2A00;
pub const POLYGON_OFFSET_FACTOR: u64 = 0x8038;
pub const TEXTURE_BINDING_2D: u64 = 0x8069;
pub const MAX_RENDERBUFFER_SIZE: u64 = 0x84E8;
pub const SAMPLE_BUFFERS: u64 = 0x80A8;
pub const SAMPLES: u64 = 0x80A9;
pub const SAMPLE_COVERAGE_VALUE: u64 = 0x80AA;
pub const SAMPLE_COVERAGE_INVERT: u64 = 0x80AB;
pub const COMPRESSED_TEXTURE_FORMATS: u64 = 0x86A3;
pub const FRAMEBUFFER: u64 = 0x8D40;
pub const RENDERBUFFER: u64 = 0x8D41;
pub const FRAMEBUFFER_BINDING: u64 = 0x8CA6;
pub const COLOR_ATTACHMENT0: u64 = 0x8CE0;
pub const FRAMEBUFFER_COMPLETE: u64 = 0x8CD5;
pub const FRAMEBUFFER_INCOMPLETE_ATTACHMENT: u64 = 0x8CD6;
pub const FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT: u64 = 0x8CD7;
pub const DONT_CARE: u64 = 0x1100;
pub const FASTEST: u64 = 0x1101;
pub const NICEST: u64 = 0x1102;
pub const GENERATE_MIPMAP_HINT: u64 = 0x8192;
pub const BYTE: u64 = 0x1400;
pub const UNSIGNED_BYTE: u64 = 0x1401;
pub const SHORT: u64 = 0x1402;
pub const UNSIGNED_SHORT: u64 = 0x1403;
pub const INT: u64 = 0x1404;
pub const UNSIGNED_INT: u64 = 0x1405;
pub const FLOAT: u64 = 0x1406;
pub const DEPTH_COMPONENT: u64 = 0x1902;
pub const ALPHA: u64 = 0x1906;
pub const RGB: u64 = 0x1907;
pub const RGBA: u64 = 0x1908;
pub const LUMINANCE: u64 = 0x1909;
pub const LUMINANCE_ALPHA: u64 = 0x190A;
pub const UNSIGNED_SHORT_4_4_4_4: u64 = 0x8033;
pub const UNSIGNED_SHORT_5_5_5_1: u64 = 0x8034;
pub const UNSIGNED_SHORT_5_6_5: u64 = 0x8363;
pub const FRAGMENT_SHADER: u64 = 0x8B30;
pub const VERTEX_SHADER: u64 = 0x8B31;
pub const MAX_VERTEX_ATTRIBS: u64 = 0x8869;
pub const MAX_VERTEX_UNIFORM_VECTORS: u64 = 0x8DFB;
pub const MAX_VARYING_VECTORS: u64 = 0x8DFC;
pub const MAX_COMBINED_TEXTURE_IMAGE_UNITS: u64 = 0x8B4D;
pub const MAX_VERTEX_TEXTURE_IMAGE_UNITS: u64 = 0x8B4C;
pub const MAX_TEXTURE_IMAGE_UNITS: u64 = 0x8872;
pub const MAX_FRAGMENT_UNIFORM_VECTORS: u64 = 0x8DFD;
pub const SHADER_TYPE: u64 = 0x8B4F;
pub const DELETE_STATUS: u64 = 0x8B80;
pub const COMPILE_STATUS: u64 = 0x8B81;
pub const LINK_STATUS: u64 = 0x8B82;
pub const VALIDATE_STATUS: u64 = 0x8B83;
pub const ATTACHED_SHADERS: u64 = 0x8B85;
pub const ACTIVE_UNIFORMS: u64 = 0x8B86;
pub const ACTIVE_ATTRIBUTES: u64 = 0x8B89;
pub const SHADING_LANGUAGE_VERSION: u64 = 0x8B8C;
pub const SAMPLER_2D: u64 = 0x8B5E;
pub const CURRENT_PROGRAM: u64 = 0x8B8D;
pub const NEVER: u64 = 0x0200;
pub const LESS: u64 = 0x0201;
pub const EQUAL: u64 = 0x0202;
pub const LEQUAL: u64 = 0x0203;
pub const GREATER: u64 = 0x0204;
pub const NOTEQUAL: u64 = 0x0205;
pub const GEQUAL: u64 = 0x0206;
pub const ALWAYS: u64 = 0x0207;
pub const KEEP: u64 = 0x1E00;
pub const REPLACE: u64 = 0x1E01;
pub const INCR: u64 = 0x1E02;
pub const DECR: u64 = 0x1E03;
pub const INVERT: u64 = 0x150A;
pub const INCR_WRAP: u64 = 0x8507;
pub const DECR_WRAP: u64 = 0x8508;
pub const VENDOR: u64 = 0x1F00;
pub const RENDERER: u64 = 0x1F01;
pub const VERSION: u64 = 0x1F02;

const WEBGL_UNMASKED_VENDOR: u32 = 0x9245;
const WEBGL_UNMASKED_RENDERER: u32 = 0x9246;

const chrome_masked_vendor = "WebKit";
const chrome_masked_renderer = "WebKit WebGL";
const chrome_unmasked_vendor = "Google Inc. (Apple)";
const chrome_unmasked_renderer = "ANGLE (Apple, ANGLE Metal Renderer: Apple M-series, Unspecified Version)";
const chrome_webgl_version = "WebGL 1.0 (OpenGL ES 2.0 Chromium)";
const chrome_shading_language_version = "WebGL GLSL ES 1.0 (OpenGL ES GLSL ES 1.0 Chromium)";

const ParameterValue = union(enum) {
    string: []const u8,
    int: i32,
    bool: bool,
    int_array: js.TypedArray(i32),
    float_array: js.TypedArray(f32),
};

fn glConst32(comptime value: u64) u32 {
    return @intCast(value);
}

const TextureSampleCoord = struct {
    u: f64 = 0.0,
    v: f64 = 0.0,
};

fn containsCompact(source: []const u8, comptime needle: []const u8) bool {
    if (needle.len == 0) return true;

    var needle_index: usize = 0;
    for (source) |byte| {
        if (std.ascii.isWhitespace(byte)) continue;
        if (byte == needle[needle_index]) {
            needle_index += 1;
            if (needle_index == needle.len) return true;
        } else {
            needle_index = if (byte == needle[0]) 1 else 0;
        }
    }

    return false;
}

fn fragmentColorFromSource(source: []const u8) [4]u8 {
    if (containsCompact(source, "vec4(1.0,0.0,0.0,1.0)")) return .{ 255, 0, 0, 255 };
    if (containsCompact(source, "vec4(0.0,1.0,0.0,1.0)")) return .{ 0, 255, 0, 255 };
    if (containsCompact(source, "vec4(0.0,0.0,1.0,1.0)")) return .{ 0, 0, 255, 255 };
    if (containsCompact(source, "vec4(1.0,1.0,1.0,1.0)")) return .{ 255, 255, 255, 255 };
    if (containsCompact(source, "vec4(0.0,0.0,0.0,1.0)")) return .{ 0, 0, 0, 255 };
    return .{ 0, 255, 0, 255 };
}

fn skipAsciiWhitespace(source: []const u8, index: *usize) void {
    while (index.* < source.len and std.ascii.isWhitespace(source[index.*])) : (index.* += 1) {}
}

fn isFloatLiteralByte(byte: u8) bool {
    return (byte >= '0' and byte <= '9') or byte == '.' or byte == '-' or byte == '+' or byte == 'e' or byte == 'E';
}

fn parseFloatLiteral(source: []const u8, index: *usize) ?f64 {
    skipAsciiWhitespace(source, index);
    const start = index.*;
    while (index.* < source.len and isFloatLiteralByte(source[index.*])) : (index.* += 1) {}
    if (start == index.*) return null;
    return std.fmt.parseFloat(f64, source[start..index.*]) catch return null;
}

fn textureSampleCoordFromSource(source: []const u8) TextureSampleCoord {
    var search_index = std.mem.indexOf(u8, source, "texture2D") orelse return .{};
    while (std.mem.indexOfPos(u8, source, search_index, "vec2")) |pos| {
        var index = pos + "vec2".len;
        skipAsciiWhitespace(source, &index);
        if (index >= source.len or source[index] != '(') {
            search_index = pos + "vec2".len;
            continue;
        }
        index += 1;
        const u = parseFloatLiteral(source, &index) orelse {
            search_index = pos + "vec2".len;
            continue;
        };
        skipAsciiWhitespace(source, &index);
        if (index >= source.len or source[index] != ',') {
            search_index = pos + "vec2".len;
            continue;
        }
        index += 1;
        const v = parseFloatLiteral(source, &index) orelse {
            search_index = pos + "vec2".len;
            continue;
        };
        return .{ .u = u, .v = v };
    }
    return .{};
}

fn clampColorValue(value: f64) f32 {
    if (std.math.isNan(value)) return 0.0;
    return @floatCast(std.math.clamp(value, 0.0, 1.0));
}

fn colorByte(value: f32) u8 {
    return @intFromFloat(std.math.clamp(value, 0.0, 1.0) * 255.0);
}

fn repeatedTexturePixels(pixel: [4]u8) [texture_sample_texel_count][4]u8 {
    var values: [texture_sample_texel_count][4]u8 = undefined;
    for (&values) |*target| target.* = pixel;
    return values;
}

fn storedTextureTexelCount(texture: *const WebGLTexture) usize {
    if (texture.width <= 0 or texture.height <= 0) return 0;
    const width: usize = @intCast(texture.width);
    const height: usize = @intCast(texture.height);
    return @min(texture_sample_texel_count, width * height);
}

fn textureTexelFromValues(values: []const u8, format: u32, index: usize, fallback: [4]u8) [4]u8 {
    if (format == glConst32(RGBA)) {
        const offset = index * 4;
        if (values.len >= offset + 4) return .{ values[offset], values[offset + 1], values[offset + 2], values[offset + 3] };
    }
    if (format == glConst32(RGB)) {
        const offset = index * 3;
        if (values.len >= offset + 3) return .{ values[offset], values[offset + 1], values[offset + 2], 255 };
    }
    return fallback;
}

fn setTexturePixels(texture: *WebGLTexture, pixel: [4]u8) void {
    texture.pixel_values = pixel;
    texture.texel_values = repeatedTexturePixels(pixel);
}

fn uploadTexturePixels(texture: *WebGLTexture, value: js.Value, format: u32) void {
    if (value.isNullOrUndefined()) return;
    if (value.toZig(js.TypedArray(u8))) |typed| {
        var texels = texture.texel_values;
        const texel_count = storedTextureTexelCount(texture);
        var i: usize = 0;
        while (i < texel_count) : (i += 1) {
            texels[i] = textureTexelFromValues(typed.values, format, i, texels[i]);
        }
        texture.texel_values = texels;
        texture.pixel_values = texels[0];
    } else |_| {}
}

fn textureCoordIndex(coord: f64, length: usize) usize {
    if (length == 0 or std.math.isNan(coord) or coord <= 0.0) return 0;
    const max_index = length - 1;
    if (coord >= 1.0) return max_index;
    const scaled = coord * @as(f64, @floatFromInt(length));
    return @min(@as(usize, @intFromFloat(@floor(scaled))), max_index);
}

fn sampleTexturePixel(texture: *const WebGLTexture, coord: TextureSampleCoord) [4]u8 {
    if (texture.width <= 0 or texture.height <= 0) return texture.pixel_values;
    const width: usize = @intCast(texture.width);
    const height: usize = @intCast(texture.height);
    const x = textureCoordIndex(coord.u, width);
    const y = textureCoordIndex(coord.v, height);
    const index = y * width + x;
    if (index >= texture_sample_texel_count) return texture.pixel_values;
    return texture.texel_values[index];
}

fn boundFramebufferTexture(self: *const WebGLRenderingContext) ?*WebGLTexture {
    const framebuffer = self.bound_framebuffer orelse return null;
    if (!framebuffer.isComplete()) return null;
    return framebuffer.color_attachment0;
}

fn boundTexture2D(self: *const WebGLRenderingContext) ?*WebGLTexture {
    return self.texture_units_2d[self.active_texture_unit];
}

fn fragmentDrawColor(self: *const WebGLRenderingContext, program: *const WebGLProgram, shader: *const WebGLShader) ?[4]u8 {
    if (shader.source_uses_texture2d) {
        if (program.sampler_2d_texture_unit >= self.texture_units_2d.len) return null;
        const texture = self.texture_units_2d[program.sampler_2d_texture_unit] orelse return null;
        if (texture.deleted or !texture.has_image) return null;
        return sampleTexturePixel(texture, shader.source_texture_sample_coord);
    }
    return shader.fragment_color;
}

pub fn initFromProfile(width: u32, height: u32, profile: ?*const Profile) WebGLRenderingContext {
    var ctx = WebGLRenderingContext{
        .drawing_buffer_width = width,
        .drawing_buffer_height = height,
        .viewport_values = .{ 0, 0, @intCast(width), @intCast(height) },
        .scissor_box_values = .{ 0, 0, @intCast(width), @intCast(height) },
    };
    if (profile) |loaded| {
        if (loaded.webgl.enabled) {
            if (loaded.webgl.vendor) |vendor| ctx.unmasked_vendor = vendor;
            if (loaded.webgl.renderer) |renderer| ctx.unmasked_renderer = renderer;
        }
    }
    return ctx;
}

fn WebGLObjectJsApi(comptime ObjectType: type, comptime js_name: []const u8) type {
    return struct {
        pub const bridge = js.Bridge(ObjectType);

        pub const Meta = struct {
            pub const name = js_name;
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };
    };
}

pub const WebGLBuffer = struct {
    byte_length: usize = 0,
    usage: u32 = 0,
    deleted: bool = false,

    pub const JsApi = WebGLObjectJsApi(WebGLBuffer, "WebGLBuffer");
};
pub const WebGLFramebuffer = struct {
    color_attachment0: ?*WebGLTexture = null,
    deleted: bool = false,

    fn isComplete(self: *const WebGLFramebuffer) bool {
        const texture = self.color_attachment0 orelse return false;
        return !self.deleted and !texture.deleted and texture.has_image;
    }

    pub const JsApi = WebGLObjectJsApi(WebGLFramebuffer, "WebGLFramebuffer");
};
pub const WebGLProgram = struct {
    vertex_shader: ?*WebGLShader = null,
    fragment_shader: ?*WebGLShader = null,
    sampler_2d_texture_unit: usize = 0,
    linked: bool = false,
    validated: bool = false,
    deleted: bool = false,

    fn attachedShaderCount(self: *const WebGLProgram) i32 {
        var count: i32 = 0;
        if (self.vertex_shader != null) count += 1;
        if (self.fragment_shader != null) count += 1;
        return count;
    }

    fn usesTextureSampler(self: *const WebGLProgram) bool {
        const shader = self.fragment_shader orelse return false;
        return self.linked and shader.source_uses_texture2d;
    }

    pub const JsApi = WebGLObjectJsApi(WebGLProgram, "WebGLProgram");
};
pub const WebGLRenderbuffer = OpaqueWebGLObject("WebGLRenderbuffer");
pub const WebGLShader = struct {
    shader_type: u32,
    source_len: usize = 0,
    source_has_main: bool = false,
    source_writes_position: bool = false,
    source_writes_color: bool = false,
    source_uses_texture2d: bool = false,
    source_texture_sample_coord: TextureSampleCoord = .{},
    fragment_color: [4]u8 = .{ 0, 255, 0, 255 },
    compiled: bool = false,
    deleted: bool = false,

    pub const JsApi = WebGLObjectJsApi(WebGLShader, "WebGLShader");
};
pub const WebGLTexture = struct {
    width: i32 = 0,
    height: i32 = 0,
    pixel_values: [4]u8 = .{ 0, 0, 0, 0 },
    texel_values: [texture_sample_texel_count][4]u8 = .{.{ 0, 0, 0, 0 }} ** texture_sample_texel_count,
    min_filter: u32 = glConst32(NEAREST),
    mag_filter: u32 = glConst32(NEAREST),
    wrap_s: u32 = glConst32(CLAMP_TO_EDGE),
    wrap_t: u32 = glConst32(CLAMP_TO_EDGE),
    has_image: bool = false,
    deleted: bool = false,

    pub const JsApi = WebGLObjectJsApi(WebGLTexture, "WebGLTexture");
};
pub const WebGLUniformLocation = struct {
    program: *WebGLProgram,

    pub const JsApi = WebGLObjectJsApi(WebGLUniformLocation, "WebGLUniformLocation");
};

fn OpaqueWebGLObject(comptime js_name: []const u8) type {
    return struct {
        const Self = @This();
        _pad: u8 = 0,

        pub const JsApi = WebGLObjectJsApi(Self, js_name);
    };
}

pub const WebGLShaderPrecisionFormat = struct {
    range_min: i32 = 127,
    range_max: i32 = 127,
    precision_value: i32 = 23,

    pub fn getRangeMin(self: *const WebGLShaderPrecisionFormat) i32 {
        return self.range_min;
    }

    pub fn getRangeMax(self: *const WebGLShaderPrecisionFormat) i32 {
        return self.range_max;
    }

    pub fn getPrecision(self: *const WebGLShaderPrecisionFormat) i32 {
        return self.precision_value;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(WebGLShaderPrecisionFormat);

        pub const Meta = struct {
            pub const name = "WebGLShaderPrecisionFormat";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const rangeMin = bridge.accessor(WebGLShaderPrecisionFormat.getRangeMin, null, .{});
        pub const rangeMax = bridge.accessor(WebGLShaderPrecisionFormat.getRangeMax, null, .{});
        pub const precision = bridge.accessor(WebGLShaderPrecisionFormat.getPrecision, null, .{});
    };
};

pub const WebGLActiveInfo = struct {
    name: []const u8 = "",
    size: i32 = 0,
    type: u32 = 0,

    pub fn getName(self: *const WebGLActiveInfo) []const u8 {
        return self.name;
    }

    pub fn getSize(self: *const WebGLActiveInfo) i32 {
        return self.size;
    }

    pub fn getType(self: *const WebGLActiveInfo) u32 {
        return self.type;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(WebGLActiveInfo);

        pub const Meta = struct {
            pub const name = "WebGLActiveInfo";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const name = bridge.accessor(WebGLActiveInfo.getName, null, .{});
        pub const size = bridge.accessor(WebGLActiveInfo.getSize, null, .{});
        pub const @"type" = bridge.accessor(WebGLActiveInfo.getType, null, .{});
    };
};

/// On Chrome and Safari, a call to `getSupportedExtensions` returns total of 39.
/// The reference for it lists lesser number of extensions:
/// https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/Using_Extensions#extension_list
pub const Extension = union(enum) {
    ANGLE_instanced_arrays: void,
    EXT_blend_minmax: void,
    EXT_clip_control: void,
    EXT_color_buffer_half_float: void,
    EXT_depth_clamp: void,
    EXT_disjoint_timer_query: void,
    EXT_float_blend: void,
    EXT_frag_depth: void,
    EXT_polygon_offset_clamp: void,
    EXT_shader_texture_lod: void,
    EXT_texture_compression_bptc: void,
    EXT_texture_compression_rgtc: void,
    EXT_texture_filter_anisotropic: void,
    EXT_texture_mirror_clamp_to_edge: void,
    EXT_sRGB: void,
    KHR_parallel_shader_compile: void,
    OES_element_index_uint: void,
    OES_fbo_render_mipmap: void,
    OES_standard_derivatives: void,
    OES_texture_float: void,
    OES_texture_float_linear: void,
    OES_texture_half_float: void,
    OES_texture_half_float_linear: void,
    OES_vertex_array_object: void,
    WEBGL_blend_func_extended: void,
    WEBGL_color_buffer_float: void,
    WEBGL_compressed_texture_astc: void,
    WEBGL_compressed_texture_etc: void,
    WEBGL_compressed_texture_etc1: void,
    WEBGL_compressed_texture_pvrtc: void,
    WEBGL_compressed_texture_s3tc: void,
    WEBGL_compressed_texture_s3tc_srgb: void,
    WEBGL_debug_renderer_info: *Type.WEBGL_debug_renderer_info,
    WEBGL_debug_shaders: void,
    WEBGL_depth_texture: void,
    WEBGL_draw_buffers: void,
    WEBGL_lose_context: *Type.WEBGL_lose_context,
    WEBGL_multi_draw: void,
    WEBGL_polygon_mode: void,

    /// Reified enum type from the fields of this union.
    const Kind = blk: {
        const info = @typeInfo(Extension).@"union";
        const fields = info.fields;
        var items: [fields.len]std.builtin.Type.EnumField = undefined;
        for (fields, 0..) |field, i| {
            items[i] = .{ .name = field.name, .value = i };
        }

        break :blk @Type(.{
            .@"enum" = .{
                .tag_type = std.math.IntFittingRange(0, if (fields.len == 0) 0 else fields.len - 1),
                .fields = &items,
                .decls = &.{},
                .is_exhaustive = true,
            },
        });
    };

    /// Returns the `Extension.Kind` by its name.
    fn find(name: []const u8) ?Kind {
        // Just to make you really sad, this function has to be case-insensitive.
        // So here we copy what's being done in `std.meta.stringToEnum` but replace
        // the comparison function.
        const kvs = comptime build_kvs: {
            const T = Extension.Kind;
            const EnumKV = struct { []const u8, T };
            var kvs_array: [@typeInfo(T).@"enum".fields.len]EnumKV = undefined;
            for (@typeInfo(T).@"enum".fields, 0..) |enumField, i| {
                kvs_array[i] = .{ enumField.name, @field(T, enumField.name) };
            }
            break :build_kvs kvs_array[0..];
        };
        const Map = std.StaticStringMapWithEql(Extension.Kind, std.static_string_map.eqlAsciiIgnoreCase);
        const map = Map.initComptime(kvs);
        return map.get(name);
    }

    /// Extension types.
    pub const Type = struct {
        pub const WEBGL_debug_renderer_info = struct {
            _: u8 = 0,
            pub const UNMASKED_VENDOR_WEBGL: u64 = 0x9245;
            pub const UNMASKED_RENDERER_WEBGL: u64 = 0x9246;

            pub const JsApi = struct {
                pub const bridge = js.Bridge(WEBGL_debug_renderer_info);

                pub const Meta = struct {
                    pub const name = "WEBGL_debug_renderer_info";

                    pub const prototype_chain = bridge.prototypeChain();
                    pub var class_id: bridge.ClassId = undefined;
                };

                pub const UNMASKED_VENDOR_WEBGL = bridge.property(WEBGL_debug_renderer_info.UNMASKED_VENDOR_WEBGL, .{ .template = false, .readonly = true });
                pub const UNMASKED_RENDERER_WEBGL = bridge.property(WEBGL_debug_renderer_info.UNMASKED_RENDERER_WEBGL, .{ .template = false, .readonly = true });
            };
        };

        pub const WEBGL_lose_context = struct {
            _: u8 = 0,
            pub fn loseContext(_: *const WEBGL_lose_context) void {}
            pub fn restoreContext(_: *const WEBGL_lose_context) void {}

            pub const JsApi = struct {
                pub const bridge = js.Bridge(WEBGL_lose_context);

                pub const Meta = struct {
                    pub const name = "WEBGL_lose_context";

                    pub const prototype_chain = bridge.prototypeChain();
                    pub var class_id: bridge.ClassId = undefined;
                };

                pub const loseContext = bridge.function(WEBGL_lose_context.loseContext, .{ .noop = true });
                pub const restoreContext = bridge.function(WEBGL_lose_context.restoreContext, .{ .noop = true });
            };
        };
    };
};

pub fn getParameter(self: *const WebGLRenderingContext, pname: u32) ParameterValue {
    return switch (pname) {
        VENDOR => .{ .string = chrome_masked_vendor },
        RENDERER => .{ .string = chrome_masked_renderer },
        VERSION => .{ .string = chrome_webgl_version },
        SHADING_LANGUAGE_VERSION => .{ .string = chrome_shading_language_version },
        WEBGL_UNMASKED_VENDOR => .{ .string = self.unmasked_vendor },
        WEBGL_UNMASKED_RENDERER => .{ .string = self.unmasked_renderer },
        ACTIVE_TEXTURE => .{ .int = @intCast(@as(usize, glConst32(TEXTURE0)) + self.active_texture_unit) },
        MAX_TEXTURE_SIZE, MAX_CUBE_MAP_TEXTURE_SIZE, MAX_RENDERBUFFER_SIZE => .{ .int = 16384 },
        MAX_VERTEX_ATTRIBS => .{ .int = 16 },
        MAX_VERTEX_TEXTURE_IMAGE_UNITS => .{ .int = 16 },
        MAX_TEXTURE_IMAGE_UNITS => .{ .int = 16 },
        MAX_COMBINED_TEXTURE_IMAGE_UNITS => .{ .int = 32 },
        MAX_VERTEX_UNIFORM_VECTORS => .{ .int = 4096 },
        MAX_FRAGMENT_UNIFORM_VECTORS => .{ .int = 1024 },
        MAX_VARYING_VECTORS => .{ .int = 30 },
        RED_BITS, GREEN_BITS, BLUE_BITS, ALPHA_BITS => .{ .int = 8 },
        DEPTH_BITS => .{ .int = 24 },
        STENCIL_BITS => .{ .int = 8 },
        SUBPIXEL_BITS => .{ .int = 4 },
        SAMPLE_BUFFERS => .{ .int = 1 },
        SAMPLES => .{ .int = 4 },
        ALIASED_LINE_WIDTH_RANGE, ALIASED_POINT_SIZE_RANGE => .{ .float_array = .{ .values = &.{ 1.0, 1.0 } } },
        DEPTH_RANGE => .{ .float_array = .{ .values = &.{ 0.0, 1.0 } } },
        VIEWPORT => .{ .int_array = .{ .values = self.viewport_values[0..] } },
        SCISSOR_BOX => .{ .int_array = .{ .values = self.scissor_box_values[0..] } },
        MAX_VIEWPORT_DIMS => .{ .int_array = .{ .values = &.{ 16384, 16384 } } },
        COLOR_CLEAR_VALUE => .{ .float_array = .{ .values = self.clear_color_values[0..] } },
        COLOR_WRITEMASK => .{ .int_array = .{ .values = &.{ 1, 1, 1, 1 } } },
        DEPTH_WRITEMASK => .{ .bool = true },
        CULL_FACE, BLEND, DITHER, STENCIL_TEST, DEPTH_TEST, SCISSOR_TEST, POLYGON_OFFSET_FILL, SAMPLE_ALPHA_TO_COVERAGE, SAMPLE_COVERAGE => .{ .bool = false },
        UNPACK_ALIGNMENT, PACK_ALIGNMENT => .{ .int = 4 },
        COMPRESSED_TEXTURE_FORMATS => .{ .int_array = .{ .values = &.{} } },
        else => .{ .int = 0 },
    };
}

/// Enables a WebGL extension.
pub fn getExtension(_: *const WebGLRenderingContext, name: []const u8, frame: *Frame) !?Extension {
    const tag = Extension.find(name) orelse return null;

    return switch (tag) {
        .WEBGL_debug_renderer_info => {
            const info = try frame._factory.create(Extension.Type.WEBGL_debug_renderer_info{});
            return .{ .WEBGL_debug_renderer_info = info };
        },
        .WEBGL_lose_context => {
            const ctx = try frame._factory.create(Extension.Type.WEBGL_lose_context{});
            return .{ .WEBGL_lose_context = ctx };
        },
        inline else => |comptime_enum| @unionInit(Extension, @tagName(comptime_enum), {}),
    };
}

/// Returns a list of all the supported WebGL extensions.
pub fn getSupportedExtensions(_: *const WebGLRenderingContext) []const []const u8 {
    return std.meta.fieldNames(Extension.Kind);
}

pub const ContextAttributes = struct {
    alpha: bool = true,
    antialias: bool = true,
    depth: bool = true,
    failIfMajorPerformanceCaveat: bool = false,
    powerPreference: []const u8 = "default",
    premultipliedAlpha: bool = true,
    preserveDrawingBuffer: bool = false,
    stencil: bool = false,
    desynchronized: bool = false,
    xrCompatible: bool = false,
};

pub fn getContextAttributes(_: *const WebGLRenderingContext) ContextAttributes {
    return .{};
}

pub fn getDrawingBufferWidth(self: *const WebGLRenderingContext) u32 {
    return self.drawing_buffer_width;
}

pub fn getDrawingBufferHeight(self: *const WebGLRenderingContext) u32 {
    return self.drawing_buffer_height;
}

pub fn getError(_: *const WebGLRenderingContext) u32 {
    return NO_ERROR;
}

pub fn isContextLost(_: *const WebGLRenderingContext) bool {
    return false;
}

pub fn createBuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLBuffer {
    return frame._factory.create(WebGLBuffer{});
}

pub fn createFramebuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLFramebuffer {
    return frame._factory.create(WebGLFramebuffer{});
}

pub fn createProgram(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLProgram {
    return frame._factory.create(WebGLProgram{});
}

pub fn createRenderbuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLRenderbuffer {
    return frame._factory.create(WebGLRenderbuffer{});
}

pub fn createShader(_: *const WebGLRenderingContext, shader_type: u32, frame: *Frame) !*WebGLShader {
    return frame._factory.create(WebGLShader{ .shader_type = shader_type });
}

pub fn createTexture(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLTexture {
    return frame._factory.create(WebGLTexture{});
}

pub fn getShaderPrecisionFormat(_: *const WebGLRenderingContext, _: u32, _: u32, frame: *Frame) !*WebGLShaderPrecisionFormat {
    return frame._factory.create(WebGLShaderPrecisionFormat{});
}

pub fn shaderSource(_: *WebGLRenderingContext, shader: ?*WebGLShader, source: []const u8) void {
    const target = shader orelse return;
    target.source_len = source.len;
    target.source_has_main = containsCompact(source, "voidmain(");
    target.source_writes_position = containsCompact(source, "gl_Position");
    target.source_writes_color = containsCompact(source, "gl_FragColor");
    target.source_uses_texture2d = containsCompact(source, "texture2D(") or containsCompact(source, "sampler2D");
    target.source_texture_sample_coord = textureSampleCoordFromSource(source);
    target.fragment_color = fragmentColorFromSource(source);
    target.compiled = false;
}

pub fn compileShader(_: *WebGLRenderingContext, shader: ?*WebGLShader) void {
    const target = shader orelse return;
    if (target.deleted or target.source_len == 0 or !target.source_has_main) {
        target.compiled = false;
        return;
    }

    target.compiled = switch (target.shader_type) {
        glConst32(VERTEX_SHADER) => target.source_writes_position,
        glConst32(FRAGMENT_SHADER) => target.source_writes_color,
        else => false,
    };
}

pub fn getShaderParameter(_: *const WebGLRenderingContext, shader: ?*WebGLShader, pname: u32) ParameterValue {
    const target = shader orelse return switch (pname) {
        COMPILE_STATUS, DELETE_STATUS => .{ .bool = false },
        else => .{ .int = 0 },
    };

    return switch (pname) {
        COMPILE_STATUS => .{ .bool = target.compiled },
        DELETE_STATUS => .{ .bool = target.deleted },
        SHADER_TYPE => .{ .int = @intCast(target.shader_type) },
        else => .{ .int = 0 },
    };
}

pub fn attachShader(_: *WebGLRenderingContext, program: ?*WebGLProgram, shader: ?*WebGLShader) void {
    const target_program = program orelse return;
    const target_shader = shader orelse return;
    if (target_program.deleted or target_shader.deleted) return;

    switch (target_shader.shader_type) {
        glConst32(VERTEX_SHADER) => target_program.vertex_shader = target_shader,
        glConst32(FRAGMENT_SHADER) => target_program.fragment_shader = target_shader,
        else => return,
    }
    target_program.linked = false;
    target_program.validated = false;
}

pub fn detachShader(_: *WebGLRenderingContext, program: ?*WebGLProgram, shader: ?*WebGLShader) void {
    const target_program = program orelse return;
    const target_shader = shader orelse return;

    if (target_program.vertex_shader == target_shader) target_program.vertex_shader = null;
    if (target_program.fragment_shader == target_shader) target_program.fragment_shader = null;
    target_program.linked = false;
    target_program.validated = false;
}

pub fn linkProgram(_: *WebGLRenderingContext, program: ?*WebGLProgram) void {
    const target = program orelse return;
    const vertex_shader = target.vertex_shader orelse {
        target.linked = false;
        return;
    };
    const fragment_shader = target.fragment_shader orelse {
        target.linked = false;
        return;
    };
    target.linked = !target.deleted and
        vertex_shader.compiled and
        !vertex_shader.deleted and
        fragment_shader.compiled and
        !fragment_shader.deleted;
    target.validated = target.linked;
    target.sampler_2d_texture_unit = 0;
}

pub fn validateProgram(_: *WebGLRenderingContext, program: ?*WebGLProgram) void {
    const target = program orelse return;
    target.validated = target.linked and !target.deleted;
}

pub fn useProgram(self: *WebGLRenderingContext, program: ?*WebGLProgram) void {
    const target = program orelse {
        self.current_program = null;
        return;
    };
    self.current_program = if (target.linked and !target.deleted) target else null;
}

pub fn getProgramParameter(_: *const WebGLRenderingContext, program: ?*WebGLProgram, pname: u32) ParameterValue {
    const target = program orelse return switch (pname) {
        LINK_STATUS, VALIDATE_STATUS, DELETE_STATUS => .{ .bool = false },
        ACTIVE_ATTRIBUTES, ACTIVE_UNIFORMS, ATTACHED_SHADERS => .{ .int = 0 },
        else => .{ .int = 0 },
    };

    return switch (pname) {
        LINK_STATUS => .{ .bool = target.linked },
        VALIDATE_STATUS => .{ .bool = target.validated },
        DELETE_STATUS => .{ .bool = target.deleted },
        ACTIVE_ATTRIBUTES => .{ .int = if (target.linked) 1 else 0 },
        ACTIVE_UNIFORMS => .{ .int = if (target.usesTextureSampler()) 1 else 0 },
        ATTACHED_SHADERS => .{ .int = target.attachedShaderCount() },
        else => .{ .int = 0 },
    };
}

pub fn getShaderInfoLog(_: *const WebGLRenderingContext, shader: ?*WebGLShader) []const u8 {
    const target = shader orelse return "Missing shader";
    if (target.compiled) return "";
    if (target.source_len == 0) return "Shader source is empty";
    if (!target.source_has_main) return "Shader source has no main function";
    return "Shader source is not supported";
}

pub fn getProgramInfoLog(_: *const WebGLRenderingContext, program: ?*WebGLProgram) []const u8 {
    const target = program orelse return "Missing program";
    if (target.linked) return "";
    return "Program requires compiled vertex and fragment shaders";
}

pub fn getAttribLocation(_: *const WebGLRenderingContext, _: ?*WebGLProgram, _: []const u8) i32 {
    return 0;
}

pub fn getUniformLocation(_: *const WebGLRenderingContext, program: ?*WebGLProgram, name: []const u8, frame: *Frame) !?*WebGLUniformLocation {
    const target = program orelse return null;
    if (!target.usesTextureSampler() or !std.mem.eql(u8, name, "u_texture")) return null;
    return frame._factory.create(WebGLUniformLocation{ .program = target });
}

pub fn getActiveAttrib(_: *const WebGLRenderingContext, program: ?*WebGLProgram, index: u32, frame: *Frame) !?*WebGLActiveInfo {
    const target = program orelse return null;
    if (!target.linked or index != 0) return null;
    return frame._factory.create(WebGLActiveInfo{
        .name = "position",
        .size = 1,
        .type = glConst32(FLOAT),
    });
}

pub fn getActiveUniform(_: *const WebGLRenderingContext, program: ?*WebGLProgram, index: u32, frame: *Frame) !?*WebGLActiveInfo {
    const target = program orelse return null;
    const fragment_shader = target.fragment_shader orelse return null;
    if (!target.linked or index != 0 or !fragment_shader.source_uses_texture2d) return null;
    return frame._factory.create(WebGLActiveInfo{
        .name = "u_texture",
        .size = 1,
        .type = glConst32(SAMPLER_2D),
    });
}

pub fn clearColor(self: *WebGLRenderingContext, r: f64, g: f64, b: f64, a: f64) void {
    self.clear_color_values = .{
        clampColorValue(r),
        clampColorValue(g),
        clampColorValue(b),
        clampColorValue(a),
    };
}

pub fn clear(self: *WebGLRenderingContext, mask: u64) void {
    if ((mask & COLOR_BUFFER_BIT) == 0) return;
    const pixel_values: [4]u8 = .{
        colorByte(self.clear_color_values[0]),
        colorByte(self.clear_color_values[1]),
        colorByte(self.clear_color_values[2]),
        colorByte(self.clear_color_values[3]),
    };
    if (self.bound_framebuffer != null) {
        if (self.boundFramebufferTexture()) |texture| {
            setTexturePixels(texture, pixel_values);
        }
        return;
    }
    self.clear_pixel_values = pixel_values;
    self.has_drawn_pixels = false;
}

pub fn viewport(self: *WebGLRenderingContext, x: i32, y: i32, width: i32, height: i32) void {
    if (width < 0 or height < 0) return;
    self.viewport_values = .{ x, y, width, height };
}

pub fn scissor(self: *WebGLRenderingContext, x: i32, y: i32, width: i32, height: i32) void {
    if (width < 0 or height < 0) return;
    self.scissor_box_values = .{ x, y, width, height };
}

pub fn readPixels(self: *const WebGLRenderingContext, _: i32, _: i32, width: i32, height: i32, _: u32, _: u32, pixels: []u8) void {
    if (width <= 0 or height <= 0) return;
    const pixel_count: usize = @intCast(width * height);
    const byte_count = @min(pixels.len, pixel_count * 4);
    const source = if (self.bound_framebuffer != null)
        if (self.boundFramebufferTexture()) |texture| texture.pixel_values else return
    else if (self.has_drawn_pixels)
        self.draw_pixel_values
    else
        self.clear_pixel_values;
    var i: usize = 0;
    while (i < byte_count) : (i += 4) {
        pixels[i] = source[0];
        if (i + 1 < byte_count) pixels[i + 1] = source[1];
        if (i + 2 < byte_count) pixels[i + 2] = source[2];
        if (i + 3 < byte_count) pixels[i + 3] = source[3];
    }
}

pub fn bindBuffer(self: *WebGLRenderingContext, target: u32, buffer: ?*WebGLBuffer) void {
    if (target != glConst32(ARRAY_BUFFER)) return;
    self.bound_array_buffer = buffer;
}

pub fn bindFramebuffer(self: *WebGLRenderingContext, target: u32, framebuffer: ?*WebGLFramebuffer) void {
    if (target != glConst32(FRAMEBUFFER)) return;
    self.bound_framebuffer = framebuffer;
}

pub fn bindTexture(self: *WebGLRenderingContext, target: u32, texture: ?*WebGLTexture) void {
    if (target != glConst32(TEXTURE_2D)) return;
    self.texture_units_2d[self.active_texture_unit] = texture;
}

pub fn activeTexture(self: *WebGLRenderingContext, texture: u32) void {
    const texture0 = glConst32(TEXTURE0);
    if (texture < texture0) return;
    const unit: usize = @intCast(texture - texture0);
    if (unit >= self.texture_units_2d.len) return;
    self.active_texture_unit = unit;
}

pub fn bufferData(self: *WebGLRenderingContext, target: u32, _: ?js.Value, usage: u32) void {
    if (target != glConst32(ARRAY_BUFFER)) return;
    const buffer = self.bound_array_buffer orelse return;
    if (buffer.deleted) return;
    buffer.byte_length = 1;
    buffer.usage = usage;
}

pub fn enableVertexAttribArray(self: *WebGLRenderingContext, index: u32) void {
    if (index == 0) self.attrib0_array_enabled = true;
}

pub fn disableVertexAttribArray(self: *WebGLRenderingContext, index: u32) void {
    if (index == 0) {
        self.attrib0_array_enabled = false;
        self.attrib0_pointer_enabled = false;
    }
}

pub fn vertexAttribPointer(self: *WebGLRenderingContext, index: u32, size: i32, typ: u32, _: bool, _: i32, _: i32) void {
    if (index != 0) return;
    self.attrib0_pointer_enabled = size >= 2 and typ == glConst32(FLOAT) and self.bound_array_buffer != null;
}

pub fn drawArrays(self: *WebGLRenderingContext, mode: u32, first: i32, count: i32) void {
    if (mode != glConst32(TRIANGLES) or first < 0 or count < 3) return;
    if (!self.attrib0_array_enabled or !self.attrib0_pointer_enabled) return;
    const buffer = self.bound_array_buffer orelse return;
    if (buffer.deleted or buffer.byte_length == 0) return;
    const program = self.current_program orelse return;
    if (!program.linked or program.deleted) return;
    const fragment_shader = program.fragment_shader orelse return;
    if (!fragment_shader.compiled or fragment_shader.deleted) return;

    const pixel_values = self.fragmentDrawColor(program, fragment_shader) orelse return;
    if (self.bound_framebuffer != null) {
        if (self.boundFramebufferTexture()) |texture| {
            setTexturePixels(texture, pixel_values);
            texture.has_image = true;
        }
        return;
    }
    self.draw_pixel_values = pixel_values;
    self.has_drawn_pixels = true;
}

pub fn texImage2D(
    self: *WebGLRenderingContext,
    target: u32,
    level: i32,
    internal_format: u32,
    width: i32,
    height: i32,
    border: i32,
    format: u32,
    typ: u32,
    pixels: ?js.Value,
) void {
    if (target != glConst32(TEXTURE_2D) or level != 0 or width <= 0 or height <= 0 or border != 0) return;
    if (typ != glConst32(UNSIGNED_BYTE)) return;
    if (internal_format != glConst32(RGBA) and internal_format != glConst32(RGB)) return;
    if (format != glConst32(RGBA) and format != glConst32(RGB)) return;
    const texture = self.boundTexture2D() orelse return;
    if (texture.deleted) return;

    texture.width = width;
    texture.height = height;
    if (pixels) |value| {
        uploadTexturePixels(texture, value, format);
    } else {
        setTexturePixels(texture, .{ 0, 0, 0, 0 });
    }
    texture.has_image = true;
}

pub fn texParameteri(self: *WebGLRenderingContext, target: u32, pname: u32, param: u32) void {
    if (target != glConst32(TEXTURE_2D)) return;
    const texture = self.boundTexture2D() orelse return;
    if (texture.deleted) return;
    switch (pname) {
        glConst32(TEXTURE_MIN_FILTER) => texture.min_filter = param,
        glConst32(TEXTURE_MAG_FILTER) => texture.mag_filter = param,
        glConst32(TEXTURE_WRAP_S) => texture.wrap_s = param,
        glConst32(TEXTURE_WRAP_T) => texture.wrap_t = param,
        else => return,
    }
}

pub fn framebufferTexture2D(
    self: *WebGLRenderingContext,
    target: u32,
    attachment: u32,
    textarget: u32,
    texture: ?*WebGLTexture,
    level: i32,
) void {
    if (target != glConst32(FRAMEBUFFER) or attachment != glConst32(COLOR_ATTACHMENT0)) return;
    if (textarget != glConst32(TEXTURE_2D) or level != 0) return;
    const framebuffer = self.bound_framebuffer orelse return;
    if (framebuffer.deleted) return;
    framebuffer.color_attachment0 = texture;
}

pub fn checkFramebufferStatus(self: *const WebGLRenderingContext, target: u32) u32 {
    if (target != glConst32(FRAMEBUFFER)) return glConst32(FRAMEBUFFER_INCOMPLETE_ATTACHMENT);
    const framebuffer = self.bound_framebuffer orelse return glConst32(FRAMEBUFFER_COMPLETE);
    const texture = framebuffer.color_attachment0 orelse return glConst32(FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT);
    if (framebuffer.deleted or texture.deleted or !texture.has_image) {
        return glConst32(FRAMEBUFFER_INCOMPLETE_ATTACHMENT);
    }
    return glConst32(FRAMEBUFFER_COMPLETE);
}

pub fn isFramebuffer(_: *const WebGLRenderingContext, framebuffer: ?*WebGLFramebuffer) bool {
    const target = framebuffer orelse return false;
    return !target.deleted;
}

pub fn isTexture(_: *const WebGLRenderingContext, texture: ?*WebGLTexture) bool {
    const target = texture orelse return false;
    return !target.deleted;
}

pub fn deleteBuffer(self: *WebGLRenderingContext, buffer: ?*WebGLBuffer) void {
    const target = buffer orelse return;
    target.deleted = true;
    target.byte_length = 0;
    if (self.bound_array_buffer == target) self.bound_array_buffer = null;
}

pub fn deleteFramebuffer(self: *WebGLRenderingContext, framebuffer: ?*WebGLFramebuffer) void {
    const target = framebuffer orelse return;
    target.deleted = true;
    target.color_attachment0 = null;
    if (self.bound_framebuffer == target) self.bound_framebuffer = null;
}

pub fn deleteProgram(self: *WebGLRenderingContext, program: ?*WebGLProgram) void {
    const target = program orelse return;
    target.deleted = true;
    target.linked = false;
    target.validated = false;
    target.sampler_2d_texture_unit = 0;
    if (self.current_program == target) self.current_program = null;
}

pub fn deleteShader(_: *WebGLRenderingContext, shader: ?*WebGLShader) void {
    const target = shader orelse return;
    target.deleted = true;
    target.compiled = false;
}

pub fn deleteTexture(self: *WebGLRenderingContext, texture: ?*WebGLTexture) void {
    const target = texture orelse return;
    target.deleted = true;
    target.has_image = false;
    for (&self.texture_units_2d) |*unit| {
        if (unit.* == target) unit.* = null;
    }
    if (self.bound_framebuffer) |framebuffer| {
        if (framebuffer.color_attachment0 == target) framebuffer.color_attachment0 = null;
    }
}

pub fn uniform1i(_: *WebGLRenderingContext, location: ?*WebGLUniformLocation, value: i32) void {
    const target = location orelse return;
    const program = target.program;
    if (!program.usesTextureSampler() or value < 0) return;
    const unit: usize = @intCast(value);
    if (unit >= texture_unit_count) return;
    program.sampler_2d_texture_unit = unit;
}

pub fn noop(_: *const WebGLRenderingContext) void {}
pub fn noop1(_: *const WebGLRenderingContext, _: ?js.Value) void {}
pub fn noop2(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value) void {}
pub fn noop3(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value, _: ?js.Value) void {}
pub fn noop4(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value) void {}
pub fn noop5(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value) void {}
pub fn noop6(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value) void {}
pub fn noop7(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value) void {}
pub fn noop8(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value) void {}
pub fn noop9(_: *const WebGLRenderingContext, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value, _: ?js.Value) void {}

pub const JsApi = struct {
    pub const bridge = js.Bridge(WebGLRenderingContext);

    pub const Meta = struct {
        pub const name = "WebGLRenderingContext";

        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const getParameter = bridge.function(WebGLRenderingContext.getParameter, .{});
    pub const getExtension = bridge.function(WebGLRenderingContext.getExtension, .{});
    pub const getSupportedExtensions = bridge.function(WebGLRenderingContext.getSupportedExtensions, .{});
    pub const getContextAttributes = bridge.function(WebGLRenderingContext.getContextAttributes, .{});
    pub const getError = bridge.function(WebGLRenderingContext.getError, .{});
    pub const isContextLost = bridge.function(WebGLRenderingContext.isContextLost, .{});
    pub const createBuffer = bridge.function(WebGLRenderingContext.createBuffer, .{});
    pub const createFramebuffer = bridge.function(WebGLRenderingContext.createFramebuffer, .{});
    pub const createProgram = bridge.function(WebGLRenderingContext.createProgram, .{});
    pub const createRenderbuffer = bridge.function(WebGLRenderingContext.createRenderbuffer, .{});
    pub const createShader = bridge.function(WebGLRenderingContext.createShader, .{});
    pub const createTexture = bridge.function(WebGLRenderingContext.createTexture, .{});
    pub const getShaderPrecisionFormat = bridge.function(WebGLRenderingContext.getShaderPrecisionFormat, .{});
    pub const getShaderParameter = bridge.function(WebGLRenderingContext.getShaderParameter, .{});
    pub const getProgramParameter = bridge.function(WebGLRenderingContext.getProgramParameter, .{});
    pub const getShaderInfoLog = bridge.function(WebGLRenderingContext.getShaderInfoLog, .{});
    pub const getProgramInfoLog = bridge.function(WebGLRenderingContext.getProgramInfoLog, .{});
    pub const getAttribLocation = bridge.function(WebGLRenderingContext.getAttribLocation, .{});
    pub const getUniformLocation = bridge.function(WebGLRenderingContext.getUniformLocation, .{});
    pub const getActiveAttrib = bridge.function(WebGLRenderingContext.getActiveAttrib, .{ .null_as_undefined = true });
    pub const getActiveUniform = bridge.function(WebGLRenderingContext.getActiveUniform, .{ .null_as_undefined = true });
    pub const isFramebuffer = bridge.function(WebGLRenderingContext.isFramebuffer, .{});
    pub const isTexture = bridge.function(WebGLRenderingContext.isTexture, .{});
    pub const activeTexture = bridge.function(WebGLRenderingContext.activeTexture, .{});
    pub const attachShader = bridge.function(WebGLRenderingContext.attachShader, .{});
    pub const bindAttribLocation = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const bindBuffer = bridge.function(WebGLRenderingContext.bindBuffer, .{});
    pub const bindFramebuffer = bridge.function(WebGLRenderingContext.bindFramebuffer, .{});
    pub const bindRenderbuffer = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const bindTexture = bridge.function(WebGLRenderingContext.bindTexture, .{});
    pub const blendColor = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const blendEquation = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const blendEquationSeparate = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const blendFunc = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const blendFuncSeparate = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const bufferData = bridge.function(WebGLRenderingContext.bufferData, .{});
    pub const bufferSubData = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const checkFramebufferStatus = bridge.function(WebGLRenderingContext.checkFramebufferStatus, .{});
    pub const clear = bridge.function(WebGLRenderingContext.clear, .{});
    pub const clearColor = bridge.function(WebGLRenderingContext.clearColor, .{});
    pub const clearDepth = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const clearStencil = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const colorMask = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const compileShader = bridge.function(WebGLRenderingContext.compileShader, .{});
    pub const compressedTexImage2D = bridge.function(WebGLRenderingContext.noop7, .{ .noop = true });
    pub const compressedTexSubImage2D = bridge.function(WebGLRenderingContext.noop8, .{ .noop = true });
    pub const copyTexImage2D = bridge.function(WebGLRenderingContext.noop8, .{ .noop = true });
    pub const copyTexSubImage2D = bridge.function(WebGLRenderingContext.noop8, .{ .noop = true });
    pub const cullFace = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteBuffer = bridge.function(WebGLRenderingContext.deleteBuffer, .{});
    pub const deleteFramebuffer = bridge.function(WebGLRenderingContext.deleteFramebuffer, .{});
    pub const deleteProgram = bridge.function(WebGLRenderingContext.deleteProgram, .{});
    pub const deleteRenderbuffer = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteShader = bridge.function(WebGLRenderingContext.deleteShader, .{});
    pub const deleteTexture = bridge.function(WebGLRenderingContext.deleteTexture, .{});
    pub const depthFunc = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const depthMask = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const depthRange = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const detachShader = bridge.function(WebGLRenderingContext.detachShader, .{});
    pub const disable = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const disableVertexAttribArray = bridge.function(WebGLRenderingContext.disableVertexAttribArray, .{});
    pub const drawArrays = bridge.function(WebGLRenderingContext.drawArrays, .{});
    pub const drawElements = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const enable = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const enableVertexAttribArray = bridge.function(WebGLRenderingContext.enableVertexAttribArray, .{});
    pub const finish = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const flush = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const framebufferRenderbuffer = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const framebufferTexture2D = bridge.function(WebGLRenderingContext.framebufferTexture2D, .{});
    pub const frontFace = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const generateMipmap = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const hint = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const lineWidth = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const linkProgram = bridge.function(WebGLRenderingContext.linkProgram, .{});
    pub const pixelStorei = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const polygonOffset = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const readPixels = bridge.function(WebGLRenderingContext.readPixels, .{});
    pub const renderbufferStorage = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const sampleCoverage = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const scissor = bridge.function(WebGLRenderingContext.scissor, .{});
    pub const shaderSource = bridge.function(WebGLRenderingContext.shaderSource, .{});
    pub const stencilFunc = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const stencilFuncSeparate = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const stencilMask = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const stencilMaskSeparate = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const stencilOp = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const stencilOpSeparate = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const texImage2D = bridge.function(WebGLRenderingContext.texImage2D, .{});
    pub const texParameteri = bridge.function(WebGLRenderingContext.texParameteri, .{});
    pub const texSubImage2D = bridge.function(WebGLRenderingContext.noop9, .{ .noop = true });
    pub const uniform1f = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const uniform1i = bridge.function(WebGLRenderingContext.uniform1i, .{});
    pub const uniform2f = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const uniform2i = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const uniform3f = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const uniform3i = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const uniform4f = bridge.function(WebGLRenderingContext.noop5, .{ .noop = true });
    pub const uniform4i = bridge.function(WebGLRenderingContext.noop5, .{ .noop = true });
    pub const useProgram = bridge.function(WebGLRenderingContext.useProgram, .{});
    pub const validateProgram = bridge.function(WebGLRenderingContext.validateProgram, .{});
    pub const vertexAttribPointer = bridge.function(WebGLRenderingContext.vertexAttribPointer, .{});
    pub const viewport = bridge.function(WebGLRenderingContext.viewport, .{});
    pub const drawingBufferWidth = bridge.accessor(WebGLRenderingContext.getDrawingBufferWidth, null, .{});
    pub const drawingBufferHeight = bridge.accessor(WebGLRenderingContext.getDrawingBufferHeight, null, .{});
    pub const VENDOR = bridge.property(WebGLRenderingContext.VENDOR, .{ .template = true });
    pub const RENDERER = bridge.property(WebGLRenderingContext.RENDERER, .{ .template = true });
    pub const VERSION = bridge.property(WebGLRenderingContext.VERSION, .{ .template = true });
    pub const SHADING_LANGUAGE_VERSION = bridge.property(WebGLRenderingContext.SHADING_LANGUAGE_VERSION, .{ .template = true });
    pub const VIEWPORT = bridge.property(WebGLRenderingContext.VIEWPORT, .{ .template = true });
    pub const SCISSOR_BOX = bridge.property(WebGLRenderingContext.SCISSOR_BOX, .{ .template = true });
    pub const COLOR_CLEAR_VALUE = bridge.property(WebGLRenderingContext.COLOR_CLEAR_VALUE, .{ .template = true });
    pub const COLOR_WRITEMASK = bridge.property(WebGLRenderingContext.COLOR_WRITEMASK, .{ .template = true });
    pub const DEPTH_WRITEMASK = bridge.property(WebGLRenderingContext.DEPTH_WRITEMASK, .{ .template = true });
    pub const DEPTH_RANGE = bridge.property(WebGLRenderingContext.DEPTH_RANGE, .{ .template = true });
    pub const CULL_FACE = bridge.property(WebGLRenderingContext.CULL_FACE, .{ .template = true });
    pub const BLEND = bridge.property(WebGLRenderingContext.BLEND, .{ .template = true });
    pub const DITHER = bridge.property(WebGLRenderingContext.DITHER, .{ .template = true });
    pub const STENCIL_TEST = bridge.property(WebGLRenderingContext.STENCIL_TEST, .{ .template = true });
    pub const DEPTH_TEST = bridge.property(WebGLRenderingContext.DEPTH_TEST, .{ .template = true });
    pub const SCISSOR_TEST = bridge.property(WebGLRenderingContext.SCISSOR_TEST, .{ .template = true });
    pub const POLYGON_OFFSET_FILL = bridge.property(WebGLRenderingContext.POLYGON_OFFSET_FILL, .{ .template = true });
    pub const SAMPLE_ALPHA_TO_COVERAGE = bridge.property(WebGLRenderingContext.SAMPLE_ALPHA_TO_COVERAGE, .{ .template = true });
    pub const SAMPLE_COVERAGE = bridge.property(WebGLRenderingContext.SAMPLE_COVERAGE, .{ .template = true });
    pub const SAMPLE_BUFFERS = bridge.property(WebGLRenderingContext.SAMPLE_BUFFERS, .{ .template = true });
    pub const SAMPLES = bridge.property(WebGLRenderingContext.SAMPLES, .{ .template = true });
    pub const UNPACK_ALIGNMENT = bridge.property(WebGLRenderingContext.UNPACK_ALIGNMENT, .{ .template = true });
    pub const PACK_ALIGNMENT = bridge.property(WebGLRenderingContext.PACK_ALIGNMENT, .{ .template = true });
    pub const COMPRESSED_TEXTURE_FORMATS = bridge.property(WebGLRenderingContext.COMPRESSED_TEXTURE_FORMATS, .{ .template = true });
    pub const MAX_TEXTURE_SIZE = bridge.property(WebGLRenderingContext.MAX_TEXTURE_SIZE, .{ .template = true });
    pub const MAX_CUBE_MAP_TEXTURE_SIZE = bridge.property(WebGLRenderingContext.MAX_CUBE_MAP_TEXTURE_SIZE, .{ .template = true });
    pub const MAX_RENDERBUFFER_SIZE = bridge.property(WebGLRenderingContext.MAX_RENDERBUFFER_SIZE, .{ .template = true });
    pub const MAX_VIEWPORT_DIMS = bridge.property(WebGLRenderingContext.MAX_VIEWPORT_DIMS, .{ .template = true });
    pub const ALIASED_LINE_WIDTH_RANGE = bridge.property(WebGLRenderingContext.ALIASED_LINE_WIDTH_RANGE, .{ .template = true });
    pub const ALIASED_POINT_SIZE_RANGE = bridge.property(WebGLRenderingContext.ALIASED_POINT_SIZE_RANGE, .{ .template = true });
    pub const MAX_VERTEX_ATTRIBS = bridge.property(WebGLRenderingContext.MAX_VERTEX_ATTRIBS, .{ .template = true });
    pub const MAX_VERTEX_UNIFORM_VECTORS = bridge.property(WebGLRenderingContext.MAX_VERTEX_UNIFORM_VECTORS, .{ .template = true });
    pub const MAX_VARYING_VECTORS = bridge.property(WebGLRenderingContext.MAX_VARYING_VECTORS, .{ .template = true });
    pub const MAX_COMBINED_TEXTURE_IMAGE_UNITS = bridge.property(WebGLRenderingContext.MAX_COMBINED_TEXTURE_IMAGE_UNITS, .{ .template = true });
    pub const MAX_VERTEX_TEXTURE_IMAGE_UNITS = bridge.property(WebGLRenderingContext.MAX_VERTEX_TEXTURE_IMAGE_UNITS, .{ .template = true });
    pub const MAX_TEXTURE_IMAGE_UNITS = bridge.property(WebGLRenderingContext.MAX_TEXTURE_IMAGE_UNITS, .{ .template = true });
    pub const MAX_FRAGMENT_UNIFORM_VECTORS = bridge.property(WebGLRenderingContext.MAX_FRAGMENT_UNIFORM_VECTORS, .{ .template = true });
    pub const FRAGMENT_SHADER = bridge.property(WebGLRenderingContext.FRAGMENT_SHADER, .{ .template = true });
    pub const VERTEX_SHADER = bridge.property(WebGLRenderingContext.VERTEX_SHADER, .{ .template = true });
    pub const HIGH_FLOAT = bridge.property(@as(u64, 0x8DF2), .{ .template = true });
    pub const MEDIUM_FLOAT = bridge.property(@as(u64, 0x8DF1), .{ .template = true });
    pub const LOW_FLOAT = bridge.property(@as(u64, 0x8DF0), .{ .template = true });
    pub const HIGH_INT = bridge.property(@as(u64, 0x8DF5), .{ .template = true });
    pub const MEDIUM_INT = bridge.property(@as(u64, 0x8DF4), .{ .template = true });
    pub const LOW_INT = bridge.property(@as(u64, 0x8DF3), .{ .template = true });
    pub const SHADER_TYPE = bridge.property(WebGLRenderingContext.SHADER_TYPE, .{ .template = true });
    pub const DELETE_STATUS = bridge.property(WebGLRenderingContext.DELETE_STATUS, .{ .template = true });
    pub const COMPILE_STATUS = bridge.property(WebGLRenderingContext.COMPILE_STATUS, .{ .template = true });
    pub const LINK_STATUS = bridge.property(WebGLRenderingContext.LINK_STATUS, .{ .template = true });
    pub const VALIDATE_STATUS = bridge.property(WebGLRenderingContext.VALIDATE_STATUS, .{ .template = true });
    pub const ATTACHED_SHADERS = bridge.property(WebGLRenderingContext.ATTACHED_SHADERS, .{ .template = true });
    pub const ACTIVE_ATTRIBUTES = bridge.property(WebGLRenderingContext.ACTIVE_ATTRIBUTES, .{ .template = true });
    pub const ACTIVE_UNIFORMS = bridge.property(WebGLRenderingContext.ACTIVE_UNIFORMS, .{ .template = true });
    pub const COLOR_BUFFER_BIT = bridge.property(WebGLRenderingContext.COLOR_BUFFER_BIT, .{ .template = true });
    pub const DEPTH_BUFFER_BIT = bridge.property(WebGLRenderingContext.DEPTH_BUFFER_BIT, .{ .template = true });
    pub const STENCIL_BUFFER_BIT = bridge.property(WebGLRenderingContext.STENCIL_BUFFER_BIT, .{ .template = true });
    pub const ARRAY_BUFFER = bridge.property(WebGLRenderingContext.ARRAY_BUFFER, .{ .template = true });
    pub const ELEMENT_ARRAY_BUFFER = bridge.property(WebGLRenderingContext.ELEMENT_ARRAY_BUFFER, .{ .template = true });
    pub const STATIC_DRAW = bridge.property(WebGLRenderingContext.STATIC_DRAW, .{ .template = true });
    pub const FLOAT = bridge.property(WebGLRenderingContext.FLOAT, .{ .template = true });
    pub const UNSIGNED_BYTE = bridge.property(WebGLRenderingContext.UNSIGNED_BYTE, .{ .template = true });
    pub const UNSIGNED_SHORT = bridge.property(WebGLRenderingContext.UNSIGNED_SHORT, .{ .template = true });
    pub const TEXTURE_2D = bridge.property(WebGLRenderingContext.TEXTURE_2D, .{ .template = true });
    pub const TEXTURE0 = bridge.property(WebGLRenderingContext.TEXTURE0, .{ .template = true });
    pub const TEXTURE1 = bridge.property(WebGLRenderingContext.TEXTURE1, .{ .template = true });
    pub const TEXTURE2 = bridge.property(WebGLRenderingContext.TEXTURE2, .{ .template = true });
    pub const TEXTURE3 = bridge.property(WebGLRenderingContext.TEXTURE3, .{ .template = true });
    pub const TEXTURE4 = bridge.property(WebGLRenderingContext.TEXTURE4, .{ .template = true });
    pub const TEXTURE5 = bridge.property(WebGLRenderingContext.TEXTURE5, .{ .template = true });
    pub const TEXTURE6 = bridge.property(WebGLRenderingContext.TEXTURE6, .{ .template = true });
    pub const TEXTURE7 = bridge.property(WebGLRenderingContext.TEXTURE7, .{ .template = true });
    pub const TEXTURE8 = bridge.property(WebGLRenderingContext.TEXTURE8, .{ .template = true });
    pub const TEXTURE9 = bridge.property(WebGLRenderingContext.TEXTURE9, .{ .template = true });
    pub const TEXTURE10 = bridge.property(WebGLRenderingContext.TEXTURE10, .{ .template = true });
    pub const TEXTURE11 = bridge.property(WebGLRenderingContext.TEXTURE11, .{ .template = true });
    pub const TEXTURE12 = bridge.property(WebGLRenderingContext.TEXTURE12, .{ .template = true });
    pub const TEXTURE13 = bridge.property(WebGLRenderingContext.TEXTURE13, .{ .template = true });
    pub const TEXTURE14 = bridge.property(WebGLRenderingContext.TEXTURE14, .{ .template = true });
    pub const TEXTURE15 = bridge.property(WebGLRenderingContext.TEXTURE15, .{ .template = true });
    pub const TEXTURE16 = bridge.property(WebGLRenderingContext.TEXTURE16, .{ .template = true });
    pub const TEXTURE17 = bridge.property(WebGLRenderingContext.TEXTURE17, .{ .template = true });
    pub const TEXTURE18 = bridge.property(WebGLRenderingContext.TEXTURE18, .{ .template = true });
    pub const TEXTURE19 = bridge.property(WebGLRenderingContext.TEXTURE19, .{ .template = true });
    pub const TEXTURE20 = bridge.property(WebGLRenderingContext.TEXTURE20, .{ .template = true });
    pub const TEXTURE21 = bridge.property(WebGLRenderingContext.TEXTURE21, .{ .template = true });
    pub const TEXTURE22 = bridge.property(WebGLRenderingContext.TEXTURE22, .{ .template = true });
    pub const TEXTURE23 = bridge.property(WebGLRenderingContext.TEXTURE23, .{ .template = true });
    pub const TEXTURE24 = bridge.property(WebGLRenderingContext.TEXTURE24, .{ .template = true });
    pub const TEXTURE25 = bridge.property(WebGLRenderingContext.TEXTURE25, .{ .template = true });
    pub const TEXTURE26 = bridge.property(WebGLRenderingContext.TEXTURE26, .{ .template = true });
    pub const TEXTURE27 = bridge.property(WebGLRenderingContext.TEXTURE27, .{ .template = true });
    pub const TEXTURE28 = bridge.property(WebGLRenderingContext.TEXTURE28, .{ .template = true });
    pub const TEXTURE29 = bridge.property(WebGLRenderingContext.TEXTURE29, .{ .template = true });
    pub const TEXTURE30 = bridge.property(WebGLRenderingContext.TEXTURE30, .{ .template = true });
    pub const TEXTURE31 = bridge.property(WebGLRenderingContext.TEXTURE31, .{ .template = true });
    pub const ACTIVE_TEXTURE = bridge.property(WebGLRenderingContext.ACTIVE_TEXTURE, .{ .template = true });
    pub const TEXTURE_MAG_FILTER = bridge.property(WebGLRenderingContext.TEXTURE_MAG_FILTER, .{ .template = true });
    pub const TEXTURE_MIN_FILTER = bridge.property(WebGLRenderingContext.TEXTURE_MIN_FILTER, .{ .template = true });
    pub const TEXTURE_WRAP_S = bridge.property(WebGLRenderingContext.TEXTURE_WRAP_S, .{ .template = true });
    pub const TEXTURE_WRAP_T = bridge.property(WebGLRenderingContext.TEXTURE_WRAP_T, .{ .template = true });
    pub const NEAREST = bridge.property(WebGLRenderingContext.NEAREST, .{ .template = true });
    pub const LINEAR = bridge.property(WebGLRenderingContext.LINEAR, .{ .template = true });
    pub const CLAMP_TO_EDGE = bridge.property(WebGLRenderingContext.CLAMP_TO_EDGE, .{ .template = true });
    pub const FRAMEBUFFER = bridge.property(WebGLRenderingContext.FRAMEBUFFER, .{ .template = true });
    pub const FRAMEBUFFER_BINDING = bridge.property(WebGLRenderingContext.FRAMEBUFFER_BINDING, .{ .template = true });
    pub const COLOR_ATTACHMENT0 = bridge.property(WebGLRenderingContext.COLOR_ATTACHMENT0, .{ .template = true });
    pub const FRAMEBUFFER_COMPLETE = bridge.property(WebGLRenderingContext.FRAMEBUFFER_COMPLETE, .{ .template = true });
    pub const FRAMEBUFFER_INCOMPLETE_ATTACHMENT = bridge.property(WebGLRenderingContext.FRAMEBUFFER_INCOMPLETE_ATTACHMENT, .{ .template = true });
    pub const FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT = bridge.property(WebGLRenderingContext.FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT, .{ .template = true });
    pub const RGBA = bridge.property(WebGLRenderingContext.RGBA, .{ .template = true });
    pub const RGB = bridge.property(WebGLRenderingContext.RGB, .{ .template = true });
    pub const TRIANGLES = bridge.property(WebGLRenderingContext.TRIANGLES, .{ .template = true });
    pub const SAMPLER_2D = bridge.property(WebGLRenderingContext.SAMPLER_2D, .{ .template = true });
};

const testing = @import("../../../testing.zig");

fn expectStringParameter(expected: []const u8, value: ParameterValue) !void {
    switch (value) {
        .string => |actual| try testing.expectString(expected, actual),
        else => try testing.expect(false),
    }
}

test "WebApi: WebGLRenderingContext uses Chimera profile WebGL values" {
    const languages = [_][]const u8{ "en-AU", "en" };
    const brands = [_]Profile.Brand{.{ .brand = "Chromium", .version = "149" }};
    const full_version_list = [_]Profile.Brand{.{ .brand = "Chromium", .version = "149.0.0.0" }};
    const form_factor = [_][]const u8{"Desktop"};
    const profile = Profile{
        .schema_version = Profile.VERSION,
        .profile_id = "lightpanda:sess-1",
        .target_domain = "example.com",
        .user_agent = "Mozilla/5.0",
        .app_version = "5.0",
        .accept_language = "en-AU,en;q=0.9",
        .languages = languages[0..],
        .headers = .{
            .user_agent = "Mozilla/5.0",
            .accept_language = "en-AU,en;q=0.9",
            .sec_ch_ua = "\"Chromium\";v=\"149\"",
            .sec_ch_ua_mobile = "?0",
            .sec_ch_ua_platform = "\"macOS\"",
            .sec_ch_ua_full_version = "\"149.0.0.0\"",
            .sec_ch_ua_full_version_list = "\"Chromium\";v=\"149.0.0.0\"",
            .sec_ch_ua_arch = "\"arm\"",
            .sec_ch_ua_bitness = "\"64\"",
            .sec_ch_ua_model = "\"\"",
            .sec_ch_ua_platform_version = "\"27.0.0\"",
        },
        .navigator = .{
            .platform = "MacIntel",
            .vendor = "Google Inc.",
            .product = "Gecko",
            .hardware_concurrency = 8,
            .device_memory = 8,
            .max_touch_points = 0,
            .webdriver = false,
        },
        .ua_data = .{
            .brands = brands[0..],
            .full_version_list = full_version_list[0..],
            .mobile = false,
            .platform = "macOS",
            .architecture = "arm",
            .bitness = "64",
            .model = "",
            .platform_version = "27.0.0",
            .ua_full_version = "149.0.0.0",
            .wow64 = false,
            .form_factor = form_factor[0..],
        },
        .seeds = .{ .canvas = 111, .audio = 222, .font = 333, .human = 444 },
        .plugins = .{ .pdf_enabled = true },
        .canvas = .{ .enabled = true, .seed = 111 },
        .audio = .{ .enabled = true, .seed = 222 },
        .webgl = .{
            .enabled = true,
            .vendor = "Google Inc. (Profile GPU)",
            .renderer = "ANGLE (Profile GPU, Chimera Renderer)",
        },
        .webrtc = .{ .enabled = false, .exit_ip = null },
        .storage = .{ .quota_bytes = 5 * 1024 * 1024 * 1024, .usage_bytes = 0 },
        .transport = .{ .impersonate_target = null, .requires_curl_impersonate = false },
        .capabilities = .{
            .requires_proxy = true,
            .requires_webrtc_exit_ip = false,
            .requires_curl_impersonate = false,
        },
    };

    const ctx = WebGLRenderingContext.initFromProfile(640, 480, &profile);

    try expectStringParameter("Google Inc. (Profile GPU)", ctx.getParameter(WEBGL_UNMASKED_VENDOR));
    try expectStringParameter("ANGLE (Profile GPU, Chimera Renderer)", ctx.getParameter(WEBGL_UNMASKED_RENDERER));
}

test "WebApi: WebGLRenderingContext" {
    try testing.htmlRunner("canvas/webgl_rendering_context.html", .{});
}
