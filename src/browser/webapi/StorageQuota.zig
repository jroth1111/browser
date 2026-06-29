// Copyright (C) 2026 Lightpanda (Selecy SAS)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

const js = @import("../js/js.zig");

const Execution = js.Execution;

pub const default_quota_bytes: u64 = 5 * 1024 * 1024 * 1024;
pub const default_usage_bytes: u64 = 0;

pub fn quotaBytes(exec: *const Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return default_quota_bytes;
    return authority.profile.storage.quota_bytes;
}

pub fn usageBytes(exec: *const Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return default_usage_bytes;
    return authority.profile.storage.usage_bytes;
}

pub fn grantedBytes(requested_quota: ?u64, exec: *const Execution) u64 {
    const quota = quotaBytes(exec);
    const requested = requested_quota orelse quota;
    return @min(requested, quota);
}
