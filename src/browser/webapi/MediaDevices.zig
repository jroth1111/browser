// Copyright (C) 2026 Lightpanda (Selecy SAS)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

const js = @import("../js/js.zig");

const EventTarget = @import("EventTarget.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ MediaDevices, MediaDeviceInfo };
}

const MediaDevices = @This();

_proto: *EventTarget,
_devices: ?[*]*MediaDeviceInfo = null,
_on_device_change: ?js.Function.Temp = null,

pub fn asEventTarget(self: *MediaDevices) *EventTarget {
    return self._proto;
}

pub fn deinit(self: *MediaDevices) void {
    if (self._on_device_change) |func| func.release();
}

pub fn enumerateDevices(self: *MediaDevices, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(try self.devices(exec));
}

pub fn getUserMedia(_: *MediaDevices, _: ?js.Value, exec: *const Execution) js.Promise {
    return notAllowed(exec);
}

pub fn getDisplayMedia(_: *MediaDevices, _: ?js.Value, exec: *const Execution) js.Promise {
    return notAllowed(exec);
}

pub fn getOnDeviceChange(self: *const MediaDevices) ?js.Function.Temp {
    return self._on_device_change;
}

pub fn setOnDeviceChange(self: *MediaDevices, cb_: ?js.Function) !void {
    if (self._on_device_change) |func| func.release();
    if (cb_) |cb| {
        self._on_device_change = try cb.tempWithThis(self);
    } else {
        self._on_device_change = null;
    }
}

fn notAllowed(exec: *const Execution) js.Promise {
    return exec.js.local.?.rejectPromise(.{ .dom_exception = .{ .err = error.NotAllowedError } });
}

fn devices(self: *MediaDevices, exec: *const Execution) ![]*MediaDeviceInfo {
    if (self._devices == null) {
        const stored = try exec._factory.create([3]*MediaDeviceInfo{
            try exec._factory.create(MediaDeviceInfo{ ._kind = "audioinput" }),
            try exec._factory.create(MediaDeviceInfo{ ._kind = "videoinput" }),
            try exec._factory.create(MediaDeviceInfo{ ._kind = "audiooutput" }),
        });
        self._devices = stored.ptr;
    }
    return self._devices.?[0..3];
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(MediaDevices);

    pub const Meta = struct {
        pub const name = "MediaDevices";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const enumerateDevices = bridge.function(MediaDevices.enumerateDevices, .{});
    pub const getUserMedia = bridge.function(MediaDevices.getUserMedia, .{});
    pub const getDisplayMedia = bridge.function(MediaDevices.getDisplayMedia, .{});
    pub const ondevicechange = bridge.accessor(MediaDevices.getOnDeviceChange, MediaDevices.setOnDeviceChange, .{});
};

const MediaDeviceInfo = struct {
    _device_id: []const u8 = "default",
    _kind: []const u8,
    _label: []const u8 = "",
    _group_id: []const u8 = "",

    pub fn getDeviceId(self: *const MediaDeviceInfo) []const u8 {
        return self._device_id;
    }

    pub fn getKind(self: *const MediaDeviceInfo) []const u8 {
        return self._kind;
    }

    pub fn getLabel(self: *const MediaDeviceInfo) []const u8 {
        return self._label;
    }

    pub fn getGroupId(self: *const MediaDeviceInfo) []const u8 {
        return self._group_id;
    }

    pub fn toJSON(self: *const MediaDeviceInfo) struct {
        deviceId: []const u8,
        kind: []const u8,
        label: []const u8,
        groupId: []const u8,
    } {
        return .{
            .deviceId = self._device_id,
            .kind = self._kind,
            .label = self._label,
            .groupId = self._group_id,
        };
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MediaDeviceInfo);

        pub const Meta = struct {
            pub const name = "MediaDeviceInfo";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const deviceId = bridge.accessor(MediaDeviceInfo.getDeviceId, null, .{});
        pub const kind = bridge.accessor(MediaDeviceInfo.getKind, null, .{});
        pub const label = bridge.accessor(MediaDeviceInfo.getLabel, null, .{});
        pub const groupId = bridge.accessor(MediaDeviceInfo.getGroupId, null, .{});
        pub const toJSON = bridge.function(MediaDeviceInfo.toJSON, .{});
    };
};

const testing = @import("../../testing.zig");
test "WebApi: MediaDevices" {
    try testing.htmlRunner("navigator/navigator.html", .{});
}
