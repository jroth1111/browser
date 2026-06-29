const js = @import("../../js/js.zig");

const TextMetrics = @This();

_width: f64,
_actual_bounding_box_left: f64 = 0,
_actual_bounding_box_right: f64 = 0,
_font_bounding_box_ascent: f64 = 10,
_font_bounding_box_descent: f64 = 2,
_actual_bounding_box_ascent: f64 = 10,
_actual_bounding_box_descent: f64 = 2,
_em_height_ascent: f64 = 10,
_em_height_descent: f64 = 2,
_alphabetic_baseline: f64 = 0,

pub fn init(width: f64) TextMetrics {
    return .{
        ._width = width,
        ._actual_bounding_box_right = width,
    };
}

pub fn getWidth(self: *const TextMetrics) f64 {
    return self._width;
}

pub fn getActualBoundingBoxLeft(self: *const TextMetrics) f64 {
    return self._actual_bounding_box_left;
}

pub fn getActualBoundingBoxRight(self: *const TextMetrics) f64 {
    return self._actual_bounding_box_right;
}

pub fn getFontBoundingBoxAscent(self: *const TextMetrics) f64 {
    return self._font_bounding_box_ascent;
}

pub fn getFontBoundingBoxDescent(self: *const TextMetrics) f64 {
    return self._font_bounding_box_descent;
}

pub fn getActualBoundingBoxAscent(self: *const TextMetrics) f64 {
    return self._actual_bounding_box_ascent;
}

pub fn getActualBoundingBoxDescent(self: *const TextMetrics) f64 {
    return self._actual_bounding_box_descent;
}

pub fn getEmHeightAscent(self: *const TextMetrics) f64 {
    return self._em_height_ascent;
}

pub fn getEmHeightDescent(self: *const TextMetrics) f64 {
    return self._em_height_descent;
}

pub fn getAlphabeticBaseline(self: *const TextMetrics) f64 {
    return self._alphabetic_baseline;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(TextMetrics);

    pub const Meta = struct {
        pub const name = "TextMetrics";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const width = bridge.accessor(TextMetrics.getWidth, null, .{});
    pub const actualBoundingBoxLeft = bridge.accessor(TextMetrics.getActualBoundingBoxLeft, null, .{});
    pub const actualBoundingBoxRight = bridge.accessor(TextMetrics.getActualBoundingBoxRight, null, .{});
    pub const fontBoundingBoxAscent = bridge.accessor(TextMetrics.getFontBoundingBoxAscent, null, .{});
    pub const fontBoundingBoxDescent = bridge.accessor(TextMetrics.getFontBoundingBoxDescent, null, .{});
    pub const actualBoundingBoxAscent = bridge.accessor(TextMetrics.getActualBoundingBoxAscent, null, .{});
    pub const actualBoundingBoxDescent = bridge.accessor(TextMetrics.getActualBoundingBoxDescent, null, .{});
    pub const emHeightAscent = bridge.accessor(TextMetrics.getEmHeightAscent, null, .{});
    pub const emHeightDescent = bridge.accessor(TextMetrics.getEmHeightDescent, null, .{});
    pub const alphabeticBaseline = bridge.accessor(TextMetrics.getAlphabeticBaseline, null, .{});
};
