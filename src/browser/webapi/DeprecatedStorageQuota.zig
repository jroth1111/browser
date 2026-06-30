// Copyright (C) 2026 Lightpanda (Selecy SAS)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

const js = @import("../js/js.zig");
const StorageQuota = @import("StorageQuota.zig");

const DeprecatedStorageQuota = @This();

_pad: bool = false,

pub fn queryUsageAndQuota(_: *const DeprecatedStorageQuota, success: js.Function, error_callback: ?js.Function, exec: *const js.Execution) !js.Undefined {
    _ = error_callback;
    try success.call(void, .{
        @as(f64, @floatFromInt(StorageQuota.usageBytes(exec))),
        @as(f64, @floatFromInt(StorageQuota.quotaBytes(exec))),
    });
    return .{};
}

pub fn requestQuota(_: *const DeprecatedStorageQuota, requested_quota: ?u64, success: js.Function, error_callback: ?js.Function, exec: *const js.Execution) !js.Undefined {
    _ = error_callback;
    try success.call(void, .{@as(f64, @floatFromInt(StorageQuota.grantedBytes(requested_quota, exec)))});
    return .{};
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(DeprecatedStorageQuota);

    pub const Meta = struct {
        pub const name = "DeprecatedStorageQuota";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const queryUsageAndQuota = bridge.function(DeprecatedStorageQuota.queryUsageAndQuota, .{ .exposed = .window });
    pub const requestQuota = bridge.function(DeprecatedStorageQuota.requestQuota, .{ .exposed = .window });
};
