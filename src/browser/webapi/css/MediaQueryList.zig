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

// zlint-disable unused-decls
const js = @import("../../js/js.zig");
const Frame = @import("../../Frame.zig");
const EventTarget = @import("../EventTarget.zig");
const MediaQuery = @import("../../css/MediaQuery.zig");

const MediaQueryList = @This();

_proto: *EventTarget,
_media: []const u8,
_on_change: ?js.Function.Temp = null,

pub fn deinit(self: *MediaQueryList) void {
    if (self._on_change) |func| func.release();
}

pub fn asEventTarget(self: *MediaQueryList) *EventTarget {
    return self._proto;
}

pub fn getMedia(self: *const MediaQueryList) []const u8 {
    return self._media;
}

/// Re-evaluates the stored query against the current viewport on every call
/// so the result stays in sync with viewport emulation. The viewport comes
/// from the page (overridable via Emulation.setDeviceMetricsOverride),
/// matching `Window.innerWidth` / `innerHeight`.
pub fn getMatches(self: *const MediaQueryList, frame: *Frame) bool {
    return MediaQuery.matches(self._media, frame._page.getViewport());
}

pub fn getOnChange(self: *const MediaQueryList) ?js.Function.Temp {
    return self._on_change;
}

pub fn setOnChange(self: *MediaQueryList, cb_: ?js.Function) !void {
    if (self._on_change) |func| func.release();
    if (cb_) |cb| {
        self._on_change = try cb.tempWithThis(self);
    } else {
        self._on_change = null;
    }
}

// Legacy aliases use the same EventTarget registration path as `change`
// listeners; Window tracks instances and dispatches viewport-crossing changes.
pub fn addListener(self: *MediaQueryList, callback: js.Function, exec: *js.Execution) !void {
    try self._proto.addEventListener("change", .{ .function = callback }, null, exec);
}

pub fn removeListener(self: *MediaQueryList, callback: js.Function, exec: *js.Execution) !void {
    try self._proto.removeEventListener("change", .{ .function = callback }, null, exec);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(MediaQueryList);

    pub const Meta = struct {
        pub const name = "MediaQueryList";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const media = bridge.accessor(MediaQueryList.getMedia, null, .{});
    pub const matches = bridge.accessor(MediaQueryList.getMatches, null, .{});
    pub const onchange = bridge.accessor(MediaQueryList.getOnChange, MediaQueryList.setOnChange, .{});
    pub const addListener = bridge.function(MediaQueryList.addListener, .{});
    pub const removeListener = bridge.function(MediaQueryList.removeListener, .{});
};

const testing = @import("../../../testing.zig");
test "WebApi: MediaQueryList" {
    try testing.htmlRunner("css/media_query_list.html", .{});
}

test "WebApi: media @-rule cascade" {
    try testing.htmlRunner("css/media_at_rule_cascade.html", .{});
}
