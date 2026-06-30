// Copyright (C) 2026  Lightpanda (Selecy SAS)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

const std = @import("std");

const HttpClient = @import("../../HttpClient.zig");
const URL = @import("../../URL.zig");

const Allocator = std.mem.Allocator;

pub fn addStrictOriginWhenCrossOriginHeader(
    headers: *HttpClient.Headers,
    allocator: Allocator,
    referrer_url: [:0]const u8,
    request_url: [:0]const u8,
) !void {
    const value = try strictOriginWhenCrossOrigin(allocator, referrer_url, request_url) orelse return;
    const header = try std.mem.concatWithSentinel(allocator, u8, &.{ "Referer: ", value }, 0);
    try headers.add(header);
}

pub fn strictOriginWhenCrossOrigin(
    allocator: Allocator,
    referrer_url: [:0]const u8,
    request_url: [:0]const u8,
) !?[:0]u8 {
    const referrer_origin = try URL.getOrigin(allocator, referrer_url) orelse return null;
    const request_origin = try URL.getOrigin(allocator, request_url) orelse return null;

    if (std.mem.eql(u8, URL.getProtocol(referrer_url), "https:") and
        std.mem.eql(u8, URL.getProtocol(request_url), "http:"))
    {
        return null;
    }

    if (std.mem.eql(u8, referrer_origin, request_origin)) {
        return try std.mem.concatWithSentinel(
            allocator,
            u8,
            &.{ referrer_origin, URL.getPathname(referrer_url), URL.getSearch(referrer_url) },
            0,
        );
    }

    return try std.mem.concatWithSentinel(allocator, u8, &.{ referrer_origin, "/" }, 0);
}

test "Referrer: strict-origin-when-cross-origin" {
    const allocator = std.testing.allocator;

    {
        const value = try strictOriginWhenCrossOrigin(
            allocator,
            "https://example.test/path?token=1#frag",
            "https://example.test/target",
        ) orelse unreachable;
        defer allocator.free(value);
        try std.testing.expectEqualStrings("https://example.test/path?token=1", value);
    }

    {
        const value = try strictOriginWhenCrossOrigin(
            allocator,
            "https://example.test/path?token=1#frag",
            "https://other.test/target",
        ) orelse unreachable;
        defer allocator.free(value);
        try std.testing.expectEqualStrings("https://example.test/", value);
    }

    try std.testing.expectEqual(
        null,
        try strictOriginWhenCrossOrigin(
            allocator,
            "https://example.test/path",
            "http://other.test/target",
        ),
    );

    try std.testing.expectEqual(
        null,
        try strictOriginWhenCrossOrigin(
            allocator,
            "about:blank",
            "https://example.test/target",
        ),
    );
}
