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

const max_rects = 32;

rects: [max_rects]Rect = undefined,
rect_count: usize = 0,

const Rect = struct {
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,

    fn contains(self: Rect, x: f64, y: f64) bool {
        return x >= self.left and x < self.right and y >= self.top and y < self.bottom;
    }
};

pub fn begin(self: *CanvasPath) void {
    self.rect_count = 0;
}

pub fn rect(self: *CanvasPath, x: f64, y: f64, width: f64, height: f64) void {
    if (width == 0 or height == 0 or self.rect_count >= max_rects) return;
    const right = x + width;
    const bottom = y + height;
    self.rects[self.rect_count] = .{
        .left = if (width < 0) right else x,
        .top = if (height < 0) bottom else y,
        .right = if (width < 0) x else right,
        .bottom = if (height < 0) y else bottom,
    };
    self.rect_count += 1;
}

pub fn isPointInPath(self: *const CanvasPath, x: f64, y: f64, maybe_fill_rule: ?[]const u8) bool {
    var count: usize = 0;
    for (self.rects[0..self.rect_count]) |path_rect| {
        if (path_rect.contains(x, y)) count += 1;
    }
    if (maybe_fill_rule) |fill_rule| {
        if (std.mem.eql(u8, fill_rule, "evenodd")) return count % 2 == 1;
    }
    return count > 0;
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
