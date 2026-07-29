// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
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
const log = lp.log;

const http = @import("../network/http.zig");

const Detector = @This();

/// Types of bot-detection challenges we can handle.
pub const ChallengeType = enum {
    kasada,
    datadome,
    none,
};

/// Result of challenge detection analysis.
pub const DetectionResult = struct {
    challenge_type: ChallengeType,
    confidence: Confidence,

    pub const Confidence = enum {
        high,
        medium,
        low,
    };
};

/// Detect whether an HTTP response is a bot-detection challenge.
/// Inspects headers, status code, and body content for known indicators.
pub fn detectChallenge(
    status: u16,
    headers: http.HeaderIterator,
    body: ?[]const u8,
) DetectionResult {
    var result = DetectionResult{
        .challenge_type = .none,
        .confidence = .low,
    };

    // Check headers first (fastest signal)
    var hdr_it = headers;
    while (hdr_it.next()) |header| {
        // Kasada header indicators
        if (std.ascii.indexOfIgnoreCase(header.name, "x-kpsdk-ct") != null or
            std.ascii.indexOfIgnoreCase(header.name, "x-kpsdk-cd") != null or
            std.ascii.indexOfIgnoreCase(header.name, "x-kpsdk-cr") != null or
            std.ascii.indexOfIgnoreCase(header.name, "x-kpsdk-uhs") != null)
        {
            result.challenge_type = .kasada;
            result.confidence = .high;
            return result;
        }

        // DataDome header indicators
        if (std.ascii.indexOfIgnoreCase(header.name, "datadome") != null or
            std.ascii.indexOfIgnoreCase(header.value, "datadome") != null)
        {
            result.challenge_type = .datadome;
            result.confidence = .high;
            return result;
        }
    }

    // Status-code heuristics
    switch (status) {
        403, 429 => {
            // Kasada typically returns 403/429 with empty or minimal body
            // DataDome returns 403 with a challenge HTML page
        },
        else => return result,
    }

    // Body analysis (more expensive, only run if status matches)
    if (body) |b| {
        // Kasada indicators in body
        if (std.mem.indexOf(u8, b, "ips.js") != null or
            std.mem.indexOf(u8, b, "p.js") != null or
            std.mem.indexOf(u8, b, "kpsdk") != null or
            std.mem.indexOf(u8, b, "__challenge") != null)
        {
            result.challenge_type = .kasada;
            result.confidence = .medium;
            return result;
        }

        // DataDome indicators in body
        if (std.mem.indexOf(u8, b, "boring_challenge") != null or
            std.mem.indexOf(u8, b, "js.datadome.co") != null or
            std.mem.indexOf(u8, b, "datadome") != null or
            std.mem.indexOf(u8, b, "captcha") != null and std.mem.indexOf(u8, b, "datadome") != null)
        {
            result.challenge_type = .datadome;
            result.confidence = .medium;
            return result;
        }

        // Empty body on 403/429 is a Kasada signal
        if (b.len == 0) {
            result.challenge_type = .kasada;
            result.confidence = .low;
        }
    } else {
        // No body on 403/429 — likely Kasada silent block
        if (status == 403 or status == 429) {
            result.challenge_type = .kasada;
            result.confidence = .low;
        }
    }

    return result;
}

/// Extract challenge-relevant cookies from response headers.
/// Returns a slice of cookie header values that contain challenge tokens.
pub fn extractChallengeCookies(
    allocator: std.mem.Allocator,
    headers: http.HeaderIterator,
    challenge_type: ChallengeType,
) ![]const []const u8 {
    var cookies: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (cookies.items) |cookie| allocator.free(cookie);
        cookies.deinit(allocator);
    }

    var hdr_it = headers;
    while (hdr_it.next()) |header| {
        if (!std.ascii.eqlIgnoreCase(header.name, "set-cookie")) continue;

        const should_extract = switch (challenge_type) {
            .kasada => std.mem.indexOf(u8, header.value, "__ddg") != null or
                std.mem.indexOf(u8, header.value, "_pk_id") != null or
                std.mem.indexOf(u8, header.value, "kpsdk") != null,
            .datadome => std.mem.indexOf(u8, header.value, "datadome") != null or
                std.mem.indexOf(u8, header.value, "dd_") != null,
            .none => false,
        };

        if (should_extract) {
            const duped = try allocator.dupe(u8, header.value);
            try cookies.append(allocator, duped);
        }
    }

    return try cookies.toOwnedSlice(allocator);
}

// ── Unit tests ──────────────────────────────────────────────────────────────

const ListHeaderIterator = http.HeaderIterator.ListHeaderIterator;

const testing = std.testing;

test "detectChallenge: Kasada header detected" {
    const headers = [_]http.Header{
        .{ .name = "X-Kpsdk-Ct", .value = "some-token" },
        .{ .name = "Content-Type", .value = "text/html" },
    };
    const result = detectChallenge(200, .{ .list = ListHeaderIterator{ .list = &headers } }, null);
    try testing.expectEqual(ChallengeType.kasada, result.challenge_type);
    try testing.expectEqual(DetectionResult.Confidence.high, result.confidence);
}

test "detectChallenge: DataDome header detected" {
    const headers = [_]http.Header{
        .{ .name = "Set-Cookie", .value = "datadome=some-value" },
    };
    const result = detectChallenge(200, .{ .list = ListHeaderIterator{ .list = &headers } }, null);
    try testing.expectEqual(ChallengeType.datadome, result.challenge_type);
    try testing.expectEqual(DetectionResult.Confidence.high, result.confidence);
}

test "detectChallenge: no challenge on normal response" {
    const headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/html" },
    };
    const result = detectChallenge(200, .{ .list = ListHeaderIterator{ .list = &headers } }, "<html>ok</html>");
    try testing.expectEqual(ChallengeType.none, result.challenge_type);
}

test "detectChallenge: Kasada body indicator on 403" {
    const headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/html" },
    };
    const body = "<script src='/path/to/ips.js'></script>";
    const result = detectChallenge(403, .{ .list = ListHeaderIterator{ .list = &headers } }, body);
    try testing.expectEqual(ChallengeType.kasada, result.challenge_type);
    try testing.expectEqual(DetectionResult.Confidence.medium, result.confidence);
}

test "detectChallenge: empty body on 403 is Kasada" {
    const headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/html" },
    };
    const result = detectChallenge(403, .{ .list = ListHeaderIterator{ .list = &headers } }, "");
    try testing.expectEqual(ChallengeType.kasada, result.challenge_type);
}
