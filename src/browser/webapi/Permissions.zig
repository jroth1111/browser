// Copyright (C) 2023-2025 Lightpanda (Selecy SAS)
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
const lp = @import("lightpanda");

const js = @import("../js/js.zig");
const Page = @import("../Page.zig");
const Execution = js.Execution;
const Geolocation = @import("Geolocation.zig");

const Allocator = std.mem.Allocator;

pub fn registerTypes() []const type {
    return &.{ Permissions, PermissionStatus };
}

pub const State = enum {
    granted,
    prompt,
    denied,
};

const Permissions = @This();

// Padding to avoid zero-size struct pointer collisions
_pad: bool = false,

const QueryDescriptor = struct {
    name: []const u8,
};

// Report the state set via CDP Browser.grantPermissions / setPermission, or a
// coherent managed default when unset.
pub fn query(_: *const Permissions, qd: QueryDescriptor, exec: *const Execution) !js.Promise {
    // R10 #33: real Chrome validates the descriptor's permission name against
    // the PermissionName enum and REJECTS the promise with a TypeError for an
    // unknown name, rather than silently resolving to "prompt". Validate first.
    if (!isValidPermissionName(qd.name)) {
        return exec.js.local.?.rejectPromise(.{
            .type_error = "Failed to execute 'query' on 'Permissions': Failed to read the 'name' property from 'PermissionDescriptor': The provided value is not a valid enum value of type PermissionName.",
        });
    }

    const arena = try exec.getArena(.tiny, "PermissionStatus");
    errdefer exec.releaseArena(arena);

    const state = exec.session.browser.permissions.get(qd.name) orelse defaultState(qd.name, exec);
    const status = try arena.create(PermissionStatus);
    status.* = .{
        ._arena = arena,
        ._state = state,
        ._name = try arena.dupe(u8, qd.name),
    };
    return exec.js.local.?.resolvePromise(status);
}

// The full set of PermissionName enum values real Chrome recognises. Anything
// outside this set causes Chrome to reject navigator.permissions.query() with
// a TypeError (not a "prompt" resolution).
const valid_permission_names = [_][]const u8{
    "geolocation",
    "notifications",
    "push",
    "midi",
    "camera",
    "microphone",
    "background-fetch",
    "background-sync",
    "persistent-storage",
    "ambient-light-sensor",
    "accelerometer",
    "gyroscope",
    "magnetometer",
    "screen-wake-lock",
    "nfc",
    "display-capture",
    "accessibility-events",
    "clipboard-read",
    "clipboard-write",
    "payment-handler",
    "idle-detection",
    "periodic-background-sync",
    "system-wake-lock",
    "storage-access",
    "window-management",
    "local-fonts",
    "top-level-storage-access",
    "speaker-selection",
};

fn isValidPermissionName(name: []const u8) bool {
    for (valid_permission_names) |valid| {
        if (std.mem.eql(u8, name, valid)) return true;
    }
    return false;
}

fn defaultState(name: []const u8, exec: *const Execution) State {
    if (std.mem.eql(u8, name, "geolocation")) {
        return geolocationPermissionState(Geolocation.permissionState(exec));
    }
    return .prompt;
}

fn geolocationPermissionState(state: Geolocation.PermissionState) State {
    return switch (state) {
        .granted => .granted,
        .prompt => .prompt,
        .denied => .denied,
    };
}

const PermissionStatus = struct {
    _rc: lp.RC(u8) = .{},
    _arena: Allocator,
    _name: []const u8,
    _state: State,

    pub fn deinit(self: *PermissionStatus, page: *Page) void {
        page.releaseArena(self._arena);
    }

    pub fn releaseRef(self: *PermissionStatus, page: *Page) void {
        self._rc.release(self, page);
    }

    pub fn acquireRef(self: *PermissionStatus) void {
        self._rc.acquire();
    }

    fn getName(self: *const PermissionStatus) []const u8 {
        return self._name;
    }

    fn getState(self: *const PermissionStatus) []const u8 {
        return @tagName(self._state);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(PermissionStatus);
        pub const Meta = struct {
            pub const name = "PermissionStatus";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const name = bridge.accessor(getName, null, .{});
        pub const state = bridge.accessor(getState, null, .{});
    };
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(Permissions);

    pub const Meta = struct {
        pub const name = "Permissions";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const query = bridge.function(Permissions.query, .{ .dom_exception = true });
};

test "WebApi: Permissions geolocation defaults are profile driven in managed mode" {
    try std.testing.expectEqual(State.granted, geolocationPermissionState(.granted));
    try std.testing.expectEqual(State.prompt, geolocationPermissionState(.prompt));
    try std.testing.expectEqual(State.denied, geolocationPermissionState(.denied));
}
