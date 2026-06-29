// Copyright (C) 2026 Lightpanda (Selecy SAS)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

const js = @import("../js/js.zig");
const DOMException = @import("DOMException.zig");

pub const TEMPORARY: u8 = 0;
pub const PERSISTENT: u8 = 1;

pub fn requestFileSystem(
    _: ?u32,
    _: ?u64,
    success: ?js.Function,
    error_callback: ?js.Function,
) !js.Undefined {
    return finishUnavailable(success, error_callback);
}

pub fn resolveLocalFileSystemURL(
    _: ?[]const u8,
    success: ?js.Function,
    error_callback: ?js.Function,
) !js.Undefined {
    return finishUnavailable(success, error_callback);
}

fn finishUnavailable(success: ?js.Function, error_callback: ?js.Function) !js.Undefined {
    if (error_callback) |callback| {
        try callback.call(void, .{DOMException.fromError(error.NotFound).?});
    } else if (success) |callback| {
        try callback.call(void, .{@as(?[]const u8, null)});
    }
    return .{};
}
