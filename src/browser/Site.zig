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

const std = @import("std");

const URL = @import("URL.zig");
const public_suffix_list = @import("../data/public_suffix_list.zig").lookup;

pub fn sameSiteHosts(lhs: []const u8, rhs: []const u8) bool {
    if (std.mem.eql(u8, lhs, rhs)) {
        return true;
    }
    return std.mem.eql(u8, registrableDomain(lhs), registrableDomain(rhs));
}

pub fn sameSiteOriginToUrl(origin: []const u8, target_url: [:0]const u8) bool {
    const origin_host = URL.getOriginHostname(origin);
    const target_host = URL.getHostname(target_url);
    if (origin_host.len == 0 or target_host.len == 0) {
        return false;
    }
    if (!std.mem.eql(u8, scheme(origin), URL.getProtocol(target_url))) {
        return false;
    }
    return sameSiteHosts(origin_host, target_host);
}

pub fn registrableDomain(host: []const u8) []const u8 {
    if (host.len == 0 or isIpAddressHost(host)) {
        return host;
    }

    var i = std.mem.lastIndexOfScalar(u8, host, '.') orelse return host;
    while (true) {
        i = std.mem.lastIndexOfScalar(u8, host[0..i], '.') orelse return host;
        const strip = i + 1;
        if (!public_suffix_list(host[strip..])) {
            return host[strip..];
        }
    }
}

fn scheme(raw: []const u8) []const u8 {
    const pos = std.mem.indexOfScalar(u8, raw, ':') orelse return "";
    return raw[0 .. pos + 1];
}

fn isIpAddressHost(host: []const u8) bool {
    return isIpv4Address(host) or (host.len >= 2 and host[0] == '[' and host[host.len - 1] == ']');
}

fn isIpv4Address(host: []const u8) bool {
    var label_count: usize = 0;
    var it = std.mem.splitScalar(u8, host, '.');
    while (it.next()) |label| {
        if (label.len == 0 or label.len > 3) {
            return false;
        }
        var value: u16 = 0;
        for (label) |byte| {
            if (!std.ascii.isDigit(byte)) {
                return false;
            }
            value = value * 10 + (byte - '0');
        }
        if (value > 255) {
            return false;
        }
        label_count += 1;
    }
    return label_count == 4;
}

const testing = @import("../testing.zig");
test "Site: registrableDomain" {
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "", "" },
        .{ "com", "com" },
        .{ "lightpanda.io", "lightpanda.io" },
        .{ "lightpanda.io", "test.lightpanda.io" },
        .{ "lightpanda.io", "first.test.lightpanda.io" },
        .{ "www.gov.uk", "www.gov.uk" },
        .{ "stats.gov.uk", "www.stats.gov.uk" },
        .{ "api.gov.uk", "api.gov.uk" },
        .{ "dev.api.gov.uk", "dev.api.gov.uk" },
        .{ "dev.api.gov.uk", "1.dev.api.gov.uk" },
        .{ "127.0.0.1", "127.0.0.1" },
        .{ "[::1]", "[::1]" },
    };
    for (cases) |c| {
        try testing.expectEqual(c.@"0", registrableDomain(c.@"1"));
    }
}

test "Site: sameSiteOriginToUrl" {
    try testing.expectEqual(true, sameSiteOriginToUrl("http://127.0.0.1:9582", "http://127.0.0.1:9585/path"));
    try testing.expectEqual(true, sameSiteOriginToUrl("https://a.lightpanda.io", "https://b.lightpanda.io/path"));
    try testing.expectEqual(false, sameSiteOriginToUrl("http://a.lightpanda.io", "https://b.lightpanda.io/path"));
    try testing.expectEqual(false, sameSiteOriginToUrl("https://a.lightpanda.io", "https://example.com/path"));
    try testing.expectEqual(false, sameSiteOriginToUrl("null", "https://example.com/path"));
}
