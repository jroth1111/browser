// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
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

const builtin = @import("builtin");

const Config = @import("../../Config.zig");
const js = @import("../js/js.zig");
const Execution = js.Execution;
const ChimeraProfile = @import("../../chimera/Profile.zig");

const NavigatorUAData = @This();

_pad: bool = false,

const Brand = ChimeraProfile.Brand;
const default_form_factor = [_][]const u8{"Desktop"};

pub fn getBrands(_: *const NavigatorUAData, exec: *const Execution) []const Brand {
    return brandList(exec);
}

pub fn getMobile(_: *const NavigatorUAData, exec: *const Execution) bool {
    if (profileUAData(exec)) |ua| {
        return ua.mobile;
    }
    return false;
}

pub fn getPlatform(_: *const NavigatorUAData, exec: *const Execution) []const u8 {
    return uaPlatform(exec);
}

pub fn toJSON(_: *const NavigatorUAData, exec: *const Execution) struct {
    brands: []const Brand,
    mobile: bool,
    platform: []const u8,
} {
    return .{
        .mobile = if (profileUAData(exec)) |ua| ua.mobile else false,
        .brands = brandList(exec),
        .platform = uaPlatform(exec),
    };
}

pub fn getHighEntropyValues(_: *const NavigatorUAData, hints: []const []const u8, exec: *const Execution) !js.Promise {
    // This should always return `brands` + `mobile` + `platform` and then whatever
    // "hints" field is requested (assuming the browser has permission), but it's
    // also valid to just return everything.

    _ = hints;

    const ua = profileUAData(exec);
    return exec.js.local.?.resolvePromise(.{
        .brands = brandList(exec),
        .mobile = if (ua) |data| data.mobile else false,
        .platform = uaPlatform(exec),
        .architecture = if (ua) |data| data.architecture else uaArchitecture(),
        .bitness = if (ua) |data| data.bitness else uaBitness(),
        .model = if (ua) |data| data.model else "",
        .platformVersion = if (ua) |data| data.platform_version else "",
        .uaFullVersion = if (ua) |data| data.ua_full_version else "1.0.0.0",
        .fullVersionList = if (ua) |data| data.full_version_list else brandList(exec),
        .wow64 = if (ua) |data| data.wow64 else false,
        .formFactor = if (ua) |data| data.form_factor else default_form_factor[0..],
    });
}

fn brandList(exec: *const Execution) []const Brand {
    if (profileUAData(exec)) |ua| {
        return ua.brands;
    }
    const out = comptime blk: {
        const src = &Config.HttpHeaders.brands;
        var arr: [src.len]Brand = undefined;
        for (src, 0..) |b, i| {
            arr[i] = .{ .brand = b.brand, .version = b.version };
        }
        const final = arr;
        break :blk final;
    };
    return &out;
}

fn uaPlatform(exec: *const Execution) []const u8 {
    if (profileUAData(exec)) |ua| {
        return ua.platform;
    }
    return switch (builtin.os.tag) {
        .macos => "macOS",
        .windows => "Windows",
        .linux => "Linux",
        .freebsd => "FreeBSD",
        else => "Unknown",
    };
}

fn profileUAData(exec: *const Execution) ?*const ChimeraProfile.UAData {
    if (exec.session.browser.http_client.getUADataOverride()) |ua| {
        return ua;
    }
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return null;
    return &authority.profile.ua_data;
}

fn uaArchitecture() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86, .x86_64 => "x86",
        .aarch64, .aarch64_be, .arm, .armeb => "arm",
        else => "",
    };
}

fn uaBitness() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64, .aarch64, .aarch64_be, .powerpc64, .powerpc64le, .riscv64 => "64",
        else => "32",
    };
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(NavigatorUAData);

    pub const Meta = struct {
        pub const name = "NavigatorUAData";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const brands = bridge.accessor(NavigatorUAData.getBrands, null, .{});
    pub const mobile = bridge.accessor(NavigatorUAData.getMobile, null, .{});
    pub const platform = bridge.accessor(NavigatorUAData.getPlatform, null, .{});
    pub const toJSON = bridge.function(NavigatorUAData.toJSON, .{});
    pub const getHighEntropyValues = bridge.function(NavigatorUAData.getHighEntropyValues, .{});
};
