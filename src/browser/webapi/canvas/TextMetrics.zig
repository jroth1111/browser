const std = @import("std");

const js = @import("../../js/js.zig");
const Seeds = @import("../../../chimera/Seeds.zig");

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

pub fn init(width: f64, font_size: f64) TextMetrics {
    const ascent = font_size * 0.75;
    const descent = font_size * 0.25;
    return .{
        ._width = width,
        ._actual_bounding_box_right = width,
        ._font_bounding_box_ascent = ascent,
        ._font_bounding_box_descent = descent,
        ._actual_bounding_box_ascent = ascent,
        ._actual_bounding_box_descent = descent,
        ._em_height_ascent = ascent,
        ._em_height_descent = descent,
    };
}

pub fn initWithSeed(width: f64, font_size: f64, seed: u64) TextMetrics {
    const metrics = init(
        noisyMetric(width, seed, 0),
        font_size,
    );
    return .{
        ._width = metrics._width,
        ._actual_bounding_box_left = noisyMetric(metrics._actual_bounding_box_left, seed, 1),
        ._actual_bounding_box_right = noisyMetric(metrics._actual_bounding_box_right, seed, 2),
        ._font_bounding_box_ascent = noisyMetric(metrics._font_bounding_box_ascent, seed, 3),
        ._font_bounding_box_descent = noisyMetric(metrics._font_bounding_box_descent, seed, 4),
        ._actual_bounding_box_ascent = noisyMetric(metrics._actual_bounding_box_ascent, seed, 5),
        ._actual_bounding_box_descent = noisyMetric(metrics._actual_bounding_box_descent, seed, 6),
        ._em_height_ascent = noisyMetric(metrics._em_height_ascent, seed, 7),
        ._em_height_descent = noisyMetric(metrics._em_height_descent, seed, 8),
        ._alphabetic_baseline = noisyMetric(metrics._alphabetic_baseline, seed, 9),
    };
}

fn noisyMetric(value: f64, seed: u64, y: i64) f64 {
    const quantized: i64 = @intFromFloat(value * 100.0);
    const mixed = Seeds.mix(seed, @bitCast(y));
    const delta = @as(i16, @intCast(mixed % 3)) - 1;
    return @as(f64, @floatFromInt(quantized + delta)) / 100.0;
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

test "seeded text metric noise remains bounded" {
    for (0..128) |seed| {
        const metric = noisyMetric(12.0, @intCast(seed), 5);
        try std.testing.expect(metric >= 11.99);
        try std.testing.expect(metric <= 12.01);
    }

    const formerly_underflowing = noisyMetric(12.0, 76624, 5);
    try std.testing.expect(formerly_underflowing >= 11.99);
    try std.testing.expect(formerly_underflowing <= 12.01);
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
