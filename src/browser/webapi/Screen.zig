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

const js = @import("../js/js.zig");
const Profile = @import("../../chimera/Profile.zig");
const Frame = @import("../Frame.zig");
const EventTarget = @import("EventTarget.zig");

pub fn registerTypes() []const type {
    return &.{
        Screen,
        Orientation,
    };
}

const Screen = @This();

_proto: *EventTarget,
_orientation: ?*Orientation = null,
_screen_width: u32 = 1920,
_screen_height: u32 = 1080,
_is_extended: bool = false,

pub fn initFromAuthority(self: *Screen, profile: *const Profile) void {
    if (profile.screen_width) |w| self._screen_width = w;
    if (profile.screen_height) |h| self._screen_height = h;
}

pub fn asEventTarget(self: *Screen) *EventTarget {
    return self._proto;
}

pub fn getOrientation(self: *Screen, frame: *Frame) !*Orientation {
    if (self._orientation) |orientation| {
        return orientation;
    }
    const orientation = try Orientation.init(frame);
    self._orientation = orientation;
    return orientation;
}

pub fn getWidth(self: *const Screen, _: *Frame) u32 {
    return self._screen_width;
}

pub fn getHeight(self: *const Screen, _: *Frame) u32 {
    return self._screen_height;
}

// Chrome's availHeight excludes OS-chrome (taskbar/dock) from the full
// screen height. That offset is a reasonable constant, but availHeight must
// still move with the real viewport height (e.g. after
// Emulation.setDeviceMetricsOverride) rather than being a frozen literal
// that only agreed with `height` at the old hardcoded 1920x1080 default.
const avail_height_os_chrome_offset: u32 = 40;

pub fn getAvailHeight(self: *const Screen, frame: *Frame) u32 {
    const height = self.getHeight(frame);
    return if (height > avail_height_os_chrome_offset) height - avail_height_os_chrome_offset else height;
}

pub fn getIsExtended(self: *const Screen) bool {
    return self._is_extended;
}

pub fn getAvailLeft(_: *const Screen) u32 {
    return 0;
}

pub fn getAvailTop(_: *const Screen) u32 {
    return 0;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Screen);

    pub const Meta = struct {
        pub const name = "Screen";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const width = bridge.accessor(Screen.getWidth, null, .{});
    pub const height = bridge.accessor(Screen.getHeight, null, .{});
    pub const availWidth = bridge.accessor(Screen.getWidth, null, .{});
    pub const availHeight = bridge.accessor(Screen.getAvailHeight, null, .{});
    pub const colorDepth = bridge.property(24, .{ .template = false });
    pub const pixelDepth = bridge.property(24, .{ .template = false });
    pub const orientation = bridge.accessor(Screen.getOrientation, null, .{});
    pub const isExtended = bridge.accessor(Screen.getIsExtended, null, .{});
    pub const availLeft = bridge.accessor(Screen.getAvailLeft, null, .{});
    pub const availTop = bridge.accessor(Screen.getAvailTop, null, .{});
};

pub const Orientation = struct {
    _proto: *EventTarget,

    pub fn init(frame: *Frame) !*Orientation {
        return frame._factory.eventTarget(Orientation{
            ._proto = undefined,
        });
    }

    pub fn asEventTarget(self: *Orientation) *EventTarget {
        return self._proto;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Orientation);

        pub const Meta = struct {
            pub const name = "ScreenOrientation";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const angle = bridge.property(0, .{ .template = false });
        pub const @"type" = bridge.property("landscape-primary", .{ .template = false });
    };
};
