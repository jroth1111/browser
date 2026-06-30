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

const CanvasPath = @This();

const max_segments = 256;

segments_buf: [max_segments]Segment = undefined,
segment_count: usize = 0,
current: Point = .{},
subpath_start: Point = .{},
has_current: bool = false,

pub const FillRule = enum {
    nonzero,
    evenodd,
};

pub const Point = struct {
    x: f64 = 0,
    y: f64 = 0,
};

pub const Segment = struct {
    start: Point,
    end: Point,
};

pub fn begin(self: *CanvasPath) void {
    self.segment_count = 0;
    self.current = .{};
    self.subpath_start = .{};
    self.has_current = false;
}

pub fn isEmpty(self: *const CanvasPath) bool {
    return self.segment_count == 0;
}

pub fn segments(self: *const CanvasPath) []const Segment {
    return self.segments_buf[0..self.segment_count];
}

pub fn moveTo(self: *CanvasPath, x: f64, y: f64) void {
    if (!finite(x) or !finite(y)) return;
    const point = Point{ .x = x, .y = y };
    self.current = point;
    self.subpath_start = point;
    self.has_current = true;
}

pub fn lineTo(self: *CanvasPath, x: f64, y: f64) void {
    if (!finite(x) or !finite(y)) return;
    const point = Point{ .x = x, .y = y };
    if (!self.has_current) {
        self.moveTo(x, y);
        return;
    }
    self.appendSegment(self.current, point);
    self.current = point;
}

pub fn closePath(self: *CanvasPath) void {
    if (!self.has_current) return;
    if (pointsEqual(self.current, self.subpath_start)) return;
    self.appendSegment(self.current, self.subpath_start);
    self.current = self.subpath_start;
}

pub fn rect(self: *CanvasPath, x: f64, y: f64, width: f64, height: f64) void {
    if (!finite(x) or !finite(y) or !finite(width) or !finite(height)) return;
    if (width == 0 or height == 0) return;
    const right = x + width;
    const bottom = y + height;
    const left = @min(x, right);
    const top = @min(y, bottom);
    const normalized_right = @max(x, right);
    const normalized_bottom = @max(y, bottom);
    self.moveTo(left, top);
    self.lineTo(normalized_right, top);
    self.lineTo(normalized_right, normalized_bottom);
    self.lineTo(left, normalized_bottom);
    self.closePath();
}

pub fn quadraticCurveTo(self: *CanvasPath, cpx: f64, cpy: f64, x: f64, y: f64) void {
    if (!finite(cpx) or !finite(cpy) or !finite(x) or !finite(y)) return;
    if (!self.has_current) {
        self.moveTo(x, y);
        return;
    }
    const start = self.current;
    const segments_count: u32 = 8;
    var i: u32 = 1;
    while (i <= segments_count) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(segments_count));
        const inv_t = 1.0 - t;
        const px = inv_t * inv_t * start.x + 2.0 * inv_t * t * cpx + t * t * x;
        const py = inv_t * inv_t * start.y + 2.0 * inv_t * t * cpy + t * t * y;
        self.lineTo(px, py);
    }
}

pub fn bezierCurveTo(self: *CanvasPath, cp1x: f64, cp1y: f64, cp2x: f64, cp2y: f64, x: f64, y: f64) void {
    if (!finite(cp1x) or !finite(cp1y) or !finite(cp2x) or !finite(cp2y) or !finite(x) or !finite(y)) return;
    if (!self.has_current) {
        self.moveTo(x, y);
        return;
    }
    const start = self.current;
    const segments_count: u32 = 16;
    var i: u32 = 1;
    while (i <= segments_count) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(segments_count));
        const inv_t = 1.0 - t;
        const px = inv_t * inv_t * inv_t * start.x +
            3.0 * inv_t * inv_t * t * cp1x +
            3.0 * inv_t * t * t * cp2x +
            t * t * t * x;
        const py = inv_t * inv_t * inv_t * start.y +
            3.0 * inv_t * inv_t * t * cp1y +
            3.0 * inv_t * t * t * cp2y +
            t * t * t * y;
        self.lineTo(px, py);
    }
}

pub fn arc(self: *CanvasPath, x: f64, y: f64, radius: f64, start_angle: f64, end_angle: f64, maybe_counterclockwise: ?bool) void {
    if (!finite(x) or !finite(y) or !finite(radius) or !finite(start_angle) or !finite(end_angle)) return;
    if (radius < 0) return;
    if (radius == 0) {
        self.lineTo(x, y);
        return;
    }

    const tau = 2.0 * std.math.pi;
    const counterclockwise = maybe_counterclockwise orelse false;
    var span = end_angle - start_angle;
    if (counterclockwise) {
        if (span > 0) span -= tau * @ceil(span / tau);
        if (span == 0 and start_angle != end_angle) span = -tau;
    } else {
        if (span < 0) span += tau * @ceil(-span / tau);
        if (span == 0 and start_angle != end_angle) span = tau;
    }
    if (span == 0) return;

    const segment_count_f = @max(1.0, @ceil(@abs(span) / tau * 32.0));
    const arc_segments: u32 = @intFromFloat(@min(128.0, segment_count_f));
    const step = span / @as(f64, @floatFromInt(arc_segments));

    var i: u32 = 0;
    while (i <= arc_segments) : (i += 1) {
        const angle = start_angle + @as(f64, @floatFromInt(i)) * step;
        const px = x + radius * @cos(angle);
        const py = y + radius * @sin(angle);
        if (i == 0 and !self.has_current) {
            self.moveTo(px, py);
        } else {
            self.lineTo(px, py);
        }
    }
}

pub fn isPointInPath(self: *const CanvasPath, x: f64, y: f64, maybe_fill_rule: ?[]const u8) bool {
    return self.contains(x, y, parseFillRule(maybe_fill_rule));
}

pub fn contains(self: *const CanvasPath, x: f64, y: f64, fill_rule: FillRule) bool {
    if (!finite(x) or !finite(y)) return false;
    var winding: i32 = 0;
    var crossings: usize = 0;
    for (self.segments()) |segment| {
        const y0 = segment.start.y;
        const y1 = segment.end.y;
        if ((y0 > y) == (y1 > y)) continue;
        const x_intersection = segment.start.x + (y - y0) * (segment.end.x - segment.start.x) / (y1 - y0);
        if (x_intersection <= x) continue;
        crossings += 1;
        winding += if (y1 > y0) 1 else -1;
    }
    return switch (fill_rule) {
        .evenodd => crossings % 2 == 1,
        .nonzero => winding != 0,
    };
}

pub fn strokeContains(self: *const CanvasPath, x: f64, y: f64, line_width: f64) bool {
    if (!finite(x) or !finite(y) or !finite(line_width) or line_width <= 0) return false;
    const half_width = line_width / 2.0;
    for (self.segments()) |segment| {
        if (distanceToSegment(x, y, segment) <= half_width) return true;
    }
    return false;
}

pub fn parseFillRule(maybe_fill_rule: ?[]const u8) FillRule {
    if (maybe_fill_rule) |fill_rule| {
        if (std.mem.eql(u8, fill_rule, "evenodd")) return .evenodd;
    }
    return .nonzero;
}

fn appendSegment(self: *CanvasPath, start: Point, end: Point) void {
    if (pointsEqual(start, end) or self.segment_count >= max_segments) return;
    self.segments_buf[self.segment_count] = .{ .start = start, .end = end };
    self.segment_count += 1;
}

fn distanceToSegment(x: f64, y: f64, segment: Segment) f64 {
    const dx = segment.end.x - segment.start.x;
    const dy = segment.end.y - segment.start.y;
    const len_sq = dx * dx + dy * dy;
    if (len_sq <= 0.0000001) {
        const px = x - segment.start.x;
        const py = y - segment.start.y;
        return @sqrt(px * px + py * py);
    }
    const raw_t = ((x - segment.start.x) * dx + (y - segment.start.y) * dy) / len_sq;
    const t = @max(0.0, @min(1.0, raw_t));
    const projected_x = segment.start.x + t * dx;
    const projected_y = segment.start.y + t * dy;
    const px = x - projected_x;
    const py = y - projected_y;
    return @sqrt(px * px + py * py);
}

fn pointsEqual(a: Point, b: Point) bool {
    return a.x == b.x and a.y == b.y;
}

fn finite(value: f64) bool {
    return !std.math.isNan(value) and !std.math.isInf(value);
}

test "CanvasPath: rect winding" {
    const testing = std.testing;
    var path = CanvasPath{};
    path.rect(0, 0, 10, 10);
    path.rect(2, 2, 6, 6);

    try testing.expect(path.isPointInPath(5, 5, null));
    try testing.expect(!path.isPointInPath(5, 5, "evenodd"));
    try testing.expect(path.isPointInPath(1, 1, "evenodd"));

    path.begin();
    try testing.expect(!path.isPointInPath(5, 5, null));

    path.rect(10, 10, -10, -10);
    try testing.expect(path.isPointInPath(5, 5, null));
}

test "CanvasPath: flattened curves fill and stroke" {
    const testing = std.testing;
    var path = CanvasPath{};
    path.moveTo(2, 18);
    path.quadraticCurveTo(16, 0, 30, 18);
    path.lineTo(30, 22);
    path.lineTo(2, 22);
    path.closePath();

    try testing.expect(path.segment_count > 4);
    try testing.expect(path.isPointInPath(16, 16, null));
    try testing.expect(path.strokeContains(16, 8, 3));
    try testing.expect(!path.strokeContains(16, 30, 3));
}

test "CanvasPath: nonzero fill honors opposite winding holes" {
    const testing = std.testing;
    var path = CanvasPath{};
    path.moveTo(0, 0);
    path.lineTo(30, 0);
    path.lineTo(30, 30);
    path.lineTo(0, 30);
    path.closePath();
    path.moveTo(10, 10);
    path.lineTo(10, 20);
    path.lineTo(20, 20);
    path.lineTo(20, 10);
    path.closePath();

    try testing.expect(!path.isPointInPath(15, 15, null));
    try testing.expect(!path.isPointInPath(15, 15, "evenodd"));
    try testing.expect(path.isPointInPath(5, 5, null));
}

test "CanvasPath: arc flattens into segments" {
    const testing = std.testing;
    var path = CanvasPath{};
    path.moveTo(10, 10);
    path.arc(10, 10, 6, 0, std.math.pi, null);

    try testing.expect(path.segment_count > 4);
    try testing.expect(path.strokeContains(4, 10, 2));
    try testing.expect(!path.strokeContains(10, 2, 2));
}
