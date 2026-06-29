const std = @import("std");

const js = @import("../js/js.zig");
const ChimeraProfile = @import("../../chimera/Profile.zig");

pub fn registerTypes() []const type {
    return &.{
        Geolocation,
        GeolocationPosition,
        GeolocationCoordinates,
        GeolocationPositionError,
    };
}

const Geolocation = @This();

_pad: bool = false,

const GeolocationOptions = struct {
    enableHighAccuracy: bool = false,
    timeout: ?u32 = null,
    maximumAge: u32 = 0,
};

pub fn getCurrentPosition(
    _: *const Geolocation,
    success: js.Function,
    maybe_error: ?js.Function,
    _: ?GeolocationOptions,
    exec: *js.Execution,
) !void {
    if (managedPosition(exec)) |position| {
        try success.call(void, .{position});
        return;
    }
    if (maybe_error) |error_callback| {
        try error_callback.call(void, .{positionDenied()});
    }
}

pub fn watchPosition(
    self: *const Geolocation,
    success: js.Function,
    maybe_error: ?js.Function,
    options: ?GeolocationOptions,
    exec: *js.Execution,
) !u32 {
    try self.getCurrentPosition(success, maybe_error, options, exec);
    return 1;
}

pub fn clearWatch(_: *const Geolocation, _: u32) void {}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Geolocation);

    pub const Meta = struct {
        pub const name = "Geolocation";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const getCurrentPosition = bridge.function(Geolocation.getCurrentPosition, .{});
    pub const watchPosition = bridge.function(Geolocation.watchPosition, .{});
    pub const clearWatch = bridge.function(Geolocation.clearWatch, .{ .noop = true });
};

pub const PermissionState = enum {
    granted,
    prompt,
    denied,
};

pub fn permissionState(exec: *const js.Execution) PermissionState {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return .prompt;
    return permissionStateForProfile(authority.profile.geolocation);
}

fn permissionStateForProfile(geolocation: ?ChimeraProfile.Geolocation) PermissionState {
    return if (geolocation != null) .granted else .denied;
}

fn managedPosition(exec: *js.Execution) ?GeolocationPosition {
    const coords = managedCoordinates(exec) orelse return null;
    return .{ .coords = coords, .timestamp = @floatFromInt(std.time.milliTimestamp()) };
}

fn managedCoordinates(exec: *js.Execution) ?GeolocationCoordinates {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return null;
    return coordinatesFromProfile(authority.profile.geolocation);
}

fn coordinatesFromProfile(geolocation: ?ChimeraProfile.Geolocation) ?GeolocationCoordinates {
    const configured = geolocation orelse return null;
    return .{
        .latitude = configured.latitude,
        .longitude = configured.longitude,
        .accuracy = configured.accuracy,
    };
}

fn positionDenied() GeolocationPositionError {
    return .{
        .code = GeolocationPositionError.PERMISSION_DENIED,
        .message = "User denied Geolocation",
    };
}

test "WebApi: Geolocation managed coordinates are profile driven" {
    try std.testing.expect(coordinatesFromProfile(null) == null);
    try std.testing.expectEqual(PermissionState.denied, permissionStateForProfile(null));

    const managed = coordinatesFromProfile(.{
        .latitude = 40.7128,
        .longitude = -74.0060,
        .accuracy = 12500,
    }).?;
    try std.testing.expectEqual(@as(f64, 40.7128), managed.latitude);
    try std.testing.expectEqual(@as(f64, -74.0060), managed.longitude);
    try std.testing.expectEqual(@as(f64, 12500), managed.accuracy);
    try std.testing.expectEqual(PermissionState.granted, permissionStateForProfile(.{
        .latitude = 40.7128,
        .longitude = -74.0060,
        .accuracy = 12500,
    }));
}

pub const GeolocationPosition = struct {
    coords: GeolocationCoordinates,
    timestamp: f64,

    pub fn getCoords(self: *GeolocationPosition) *GeolocationCoordinates {
        return &self.coords;
    }

    pub fn getTimestamp(self: *const GeolocationPosition) f64 {
        return self.timestamp;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(GeolocationPosition);

        pub const Meta = struct {
            pub const name = "GeolocationPosition";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const coords = bridge.accessor(GeolocationPosition.getCoords, null, .{});
        pub const timestamp = bridge.accessor(GeolocationPosition.getTimestamp, null, .{});
    };
};

pub const GeolocationCoordinates = struct {
    latitude: f64,
    longitude: f64,
    accuracy: f64,
    altitude: ?f64 = null,
    altitudeAccuracy: ?f64 = null,
    heading: ?f64 = null,
    speed: ?f64 = null,

    pub fn getLatitude(self: *const GeolocationCoordinates) f64 {
        return self.latitude;
    }

    pub fn getLongitude(self: *const GeolocationCoordinates) f64 {
        return self.longitude;
    }

    pub fn getAccuracy(self: *const GeolocationCoordinates) f64 {
        return self.accuracy;
    }

    pub fn getAltitude(self: *const GeolocationCoordinates) ?f64 {
        return self.altitude;
    }

    pub fn getAltitudeAccuracy(self: *const GeolocationCoordinates) ?f64 {
        return self.altitudeAccuracy;
    }

    pub fn getHeading(self: *const GeolocationCoordinates) ?f64 {
        return self.heading;
    }

    pub fn getSpeed(self: *const GeolocationCoordinates) ?f64 {
        return self.speed;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(GeolocationCoordinates);

        pub const Meta = struct {
            pub const name = "GeolocationCoordinates";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const latitude = bridge.accessor(GeolocationCoordinates.getLatitude, null, .{});
        pub const longitude = bridge.accessor(GeolocationCoordinates.getLongitude, null, .{});
        pub const accuracy = bridge.accessor(GeolocationCoordinates.getAccuracy, null, .{});
        pub const altitude = bridge.accessor(GeolocationCoordinates.getAltitude, null, .{});
        pub const altitudeAccuracy = bridge.accessor(GeolocationCoordinates.getAltitudeAccuracy, null, .{});
        pub const heading = bridge.accessor(GeolocationCoordinates.getHeading, null, .{});
        pub const speed = bridge.accessor(GeolocationCoordinates.getSpeed, null, .{});
    };
};

pub const GeolocationPositionError = struct {
    pub const PERMISSION_DENIED: u8 = 1;
    pub const POSITION_UNAVAILABLE: u8 = 2;
    pub const TIMEOUT: u8 = 3;

    code: u8 = PERMISSION_DENIED,
    message: []const u8 = "User denied Geolocation",

    pub fn getCode(self: *const GeolocationPositionError) u8 {
        return self.code;
    }

    pub fn getMessage(self: *const GeolocationPositionError) []const u8 {
        return self.message;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(GeolocationPositionError);

        pub const Meta = struct {
            pub const name = "GeolocationPositionError";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const code = bridge.accessor(GeolocationPositionError.getCode, null, .{});
        pub const message = bridge.accessor(GeolocationPositionError.getMessage, null, .{});
        pub const PERMISSION_DENIED = bridge.property(GeolocationPositionError.PERMISSION_DENIED, .{ .template = true, .readonly = true });
        pub const POSITION_UNAVAILABLE = bridge.property(GeolocationPositionError.POSITION_UNAVAILABLE, .{ .template = true, .readonly = true });
        pub const TIMEOUT = bridge.property(GeolocationPositionError.TIMEOUT, .{ .template = true, .readonly = true });
    };
};
