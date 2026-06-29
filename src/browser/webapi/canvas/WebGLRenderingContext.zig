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

fn clampColorValue(value: f64) f32 {
    if (std.math.isNan(value)) return 0.0;
    return @floatCast(std.math.clamp(value, 0.0, 1.0));
}

fn colorByte(value: f32) u8 {
    return @intFromFloat(std.math.clamp(value, 0.0, 1.0) * 255.0);
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

pub const WebGLBuffer = OpaqueWebGLObject("WebGLBuffer");
pub const WebGLFramebuffer = OpaqueWebGLObject("WebGLFramebuffer");
pub const WebGLProgram = OpaqueWebGLObject("WebGLProgram");
pub const WebGLRenderbuffer = OpaqueWebGLObject("WebGLRenderbuffer");
pub const WebGLShader = OpaqueWebGLObject("WebGLShader");
pub const WebGLTexture = OpaqueWebGLObject("WebGLTexture");
pub const WebGLUniformLocation = OpaqueWebGLObject("WebGLUniformLocation");

fn OpaqueWebGLObject(comptime js_name: []const u8) type {
    return struct {
        const Self = @This();
        _pad: u8 = 0,

        pub const JsApi = struct {
            pub const bridge = js.Bridge(Self);

            pub const Meta = struct {
                pub const name = js_name;
                pub const prototype_chain = bridge.prototypeChain();
                pub var class_id: bridge.ClassId = undefined;
            };
        };
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

pub fn createShader(_: *const WebGLRenderingContext, _: u32, frame: *Frame) !*WebGLShader {
    return frame._factory.create(WebGLShader{});
}

pub fn createTexture(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLTexture {
    return frame._factory.create(WebGLTexture{});
}

pub fn getShaderPrecisionFormat(_: *const WebGLRenderingContext, _: u32, _: u32, frame: *Frame) !*WebGLShaderPrecisionFormat {
    return frame._factory.create(WebGLShaderPrecisionFormat{});
}

pub fn getShaderParameter(_: *const WebGLRenderingContext, _: ?*WebGLShader, pname: u32) ParameterValue {
    return switch (pname) {
        COMPILE_STATUS, DELETE_STATUS => .{ .bool = true },
        SHADER_TYPE => .{ .int = @intCast(FRAGMENT_SHADER) },
        else => .{ .int = 0 },
    };
}

pub fn getProgramParameter(_: *const WebGLRenderingContext, _: ?*WebGLProgram, pname: u32) ParameterValue {
    return switch (pname) {
        LINK_STATUS, VALIDATE_STATUS, DELETE_STATUS => .{ .bool = true },
        ACTIVE_ATTRIBUTES, ACTIVE_UNIFORMS, ATTACHED_SHADERS => .{ .int = 0 },
        else => .{ .int = 0 },
    };
}

pub fn getShaderInfoLog(_: *const WebGLRenderingContext, _: ?*WebGLShader) []const u8 {
    return "";
}

pub fn getProgramInfoLog(_: *const WebGLRenderingContext, _: ?*WebGLProgram) []const u8 {
    return "";
}

pub fn getAttribLocation(_: *const WebGLRenderingContext, _: ?*WebGLProgram, _: []const u8) i32 {
    return 0;
}

pub fn getUniformLocation(_: *const WebGLRenderingContext, _: ?*WebGLProgram, _: []const u8, frame: *Frame) !*WebGLUniformLocation {
    return frame._factory.create(WebGLUniformLocation{});
}

pub fn getActiveAttrib(_: *const WebGLRenderingContext, _: ?*WebGLProgram, _: u32) ?*WebGLActiveInfo {
    return null;
}

pub fn getActiveUniform(_: *const WebGLRenderingContext, _: ?*WebGLProgram, _: u32) ?*WebGLActiveInfo {
    return null;
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
    self.clear_pixel_values = .{
        colorByte(self.clear_color_values[0]),
        colorByte(self.clear_color_values[1]),
        colorByte(self.clear_color_values[2]),
        colorByte(self.clear_color_values[3]),
    };
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
    var i: usize = 0;
    while (i < byte_count) : (i += 4) {
        pixels[i] = self.clear_pixel_values[0];
        if (i + 1 < byte_count) pixels[i + 1] = self.clear_pixel_values[1];
        if (i + 2 < byte_count) pixels[i + 2] = self.clear_pixel_values[2];
        if (i + 3 < byte_count) pixels[i + 3] = self.clear_pixel_values[3];
    }
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
    pub const activeTexture = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const attachShader = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const bindAttribLocation = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const bindBuffer = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const bindFramebuffer = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const bindRenderbuffer = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const bindTexture = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const blendColor = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const blendEquation = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const blendEquationSeparate = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const blendFunc = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const blendFuncSeparate = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const bufferData = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const bufferSubData = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const clear = bridge.function(WebGLRenderingContext.clear, .{});
    pub const clearColor = bridge.function(WebGLRenderingContext.clearColor, .{});
    pub const clearDepth = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const clearStencil = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const colorMask = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const compileShader = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const compressedTexImage2D = bridge.function(WebGLRenderingContext.noop7, .{ .noop = true });
    pub const compressedTexSubImage2D = bridge.function(WebGLRenderingContext.noop8, .{ .noop = true });
    pub const copyTexImage2D = bridge.function(WebGLRenderingContext.noop8, .{ .noop = true });
    pub const copyTexSubImage2D = bridge.function(WebGLRenderingContext.noop8, .{ .noop = true });
    pub const cullFace = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteBuffer = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteFramebuffer = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteProgram = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteRenderbuffer = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteShader = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const deleteTexture = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const depthFunc = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const depthMask = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const depthRange = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const detachShader = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const disable = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const disableVertexAttribArray = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const drawArrays = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const drawElements = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const enable = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const enableVertexAttribArray = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const finish = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const flush = bridge.function(WebGLRenderingContext.noop, .{ .noop = true });
    pub const framebufferRenderbuffer = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const framebufferTexture2D = bridge.function(WebGLRenderingContext.noop5, .{ .noop = true });
    pub const frontFace = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const generateMipmap = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const hint = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const lineWidth = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const linkProgram = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const pixelStorei = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const polygonOffset = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const readPixels = bridge.function(WebGLRenderingContext.readPixels, .{});
    pub const renderbufferStorage = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const sampleCoverage = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const scissor = bridge.function(WebGLRenderingContext.scissor, .{});
    pub const shaderSource = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const stencilFunc = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const stencilFuncSeparate = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const stencilMask = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const stencilMaskSeparate = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const stencilOp = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const stencilOpSeparate = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const texImage2D = bridge.function(WebGLRenderingContext.noop9, .{ .noop = true });
    pub const texParameteri = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const texSubImage2D = bridge.function(WebGLRenderingContext.noop9, .{ .noop = true });
    pub const uniform1f = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const uniform1i = bridge.function(WebGLRenderingContext.noop2, .{ .noop = true });
    pub const uniform2f = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const uniform2i = bridge.function(WebGLRenderingContext.noop3, .{ .noop = true });
    pub const uniform3f = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const uniform3i = bridge.function(WebGLRenderingContext.noop4, .{ .noop = true });
    pub const uniform4f = bridge.function(WebGLRenderingContext.noop5, .{ .noop = true });
    pub const uniform4i = bridge.function(WebGLRenderingContext.noop5, .{ .noop = true });
    pub const useProgram = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const validateProgram = bridge.function(WebGLRenderingContext.noop1, .{ .noop = true });
    pub const vertexAttribPointer = bridge.function(WebGLRenderingContext.noop6, .{ .noop = true });
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
    pub const COMPILE_STATUS = bridge.property(WebGLRenderingContext.COMPILE_STATUS, .{ .template = true });
    pub const LINK_STATUS = bridge.property(WebGLRenderingContext.LINK_STATUS, .{ .template = true });
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
    pub const RGBA = bridge.property(WebGLRenderingContext.RGBA, .{ .template = true });
    pub const RGB = bridge.property(WebGLRenderingContext.RGB, .{ .template = true });
    pub const TRIANGLES = bridge.property(WebGLRenderingContext.TRIANGLES, .{ .template = true });
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
