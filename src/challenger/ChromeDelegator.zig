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
const posix = std.posix;

const ChallengerPool = @import("ChallengerPool.zig");
const Detector = @import("Detector.zig");

const Allocator = std.mem.Allocator;

const ChromeDelegator = @This();

allocator: Allocator,
pool: *ChallengerPool,

/// Result of a challenge delegation attempt.
pub const DelegationResult = struct {
    /// The cookies/solved tokens to inject into subsequent requests.
    solved_cookies: ?[]const u8,
    /// Whether the challenge was successfully solved.
    solved: bool,
    /// Error message if delegation failed.
    error_msg: ?[]const u8,

    pub fn deinit(self: *DelegationResult, allocator: Allocator) void {
        if (self.solved_cookies) |cookies| allocator.free(cookies);
        if (self.error_msg) |msg| allocator.free(msg);
    }
};

pub fn init(allocator: Allocator, pool: *ChallengerPool) ChromeDelegator {
    return .{
        .allocator = allocator,
        .pool = pool,
    };
}

/// Delegate a challenge to Chrome: navigate to the URL, wait for it to solve
/// the challenge, and extract the resulting cookies.
pub fn solveChallenge(
    self: *ChromeDelegator,
    challenge_url: []const u8,
    challenge_type: Detector.ChallengeType,
    proxy: ?[]const u8,
) !DelegationResult {
    _ = proxy;
    _ = proxy;
    const endpoint = self.pool.acquire() orelse {
        return .{
            .solved_cookies = null,
            .solved = false,
            .error_msg = try self.allocator.dupe(u8, "no Chrome endpoint available"),
        };
    };
    defer self.pool.release(endpoint);

    log.info(.http, "delegating challenge to Chrome", .{
        .url = challenge_url,
        .type = @tagName(challenge_type),
        .chrome_pid = endpoint.pid,
    });

    // Connect to Chrome via WebSocket and use CDP to navigate
    const result = self.cdpNavigateAndSolve(endpoint, challenge_url, challenge_type) catch |err| {
        log.err(.http, "CDP delegation failed", .{ .err = err });
        return .{
            .solved_cookies = null,
            .solved = false,
            .error_msg = try std.fmt.allocPrint(self.allocator, "CDP error: {}", .{err}),
        };
    };

    return result;
}

fn cdpNavigateAndSolve(
    self: *ChromeDelegator,
    endpoint: *ChallengerPool.ChromeEndpoint,
    url: []const u8,
    challenge_type: Detector.ChallengeType,
) !DelegationResult {
    const ws_url = endpoint.ws_url.items;

    // Parse the WebSocket URL to extract host:port
    const uri = std.Uri.parse(ws_url) catch return error.InvalidWsUrl;
    const host_component = uri.host orelse return error.InvalidWsUrl;
    var host_buf: [std.Uri.host_name_max]u8 = undefined;
    const host = host_component.toRaw(&host_buf) catch return error.InvalidWsUrl;
    const port = uri.port orelse 9222;

    // Connect to Chrome's DevTools WebSocket
    const address = std.net.Address.parseIp(host, port) catch return error.InvalidWsUrl;

    const sock = posix.socket(address.any.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, posix.IPPROTO.TCP) catch |err| {
        log.err(.http, "failed to create socket for CDP", .{ .err = err });
        return error.CdpConnectionFailed;
    };
    defer posix.close(sock);

    posix.connect(sock, &address.any, address.getOsSockLen()) catch |err| {
        log.err(.http, "failed to connect to Chrome CDP", .{ .err = err });
        return error.CdpConnectionFailed;
    };

    // Perform WebSocket handshake (simplified — real implementation would
    // do a proper RFC 6455 handshake, but for internal tooling we use a
    // minimal approach)
    try self.cdpHandshake(sock);

    // Send CDP commands to navigate and solve the challenge
    const solved_cookies = try self.cdpExecuteChallenge(sock, url, challenge_type);

    return .{
        .solved_cookies = solved_cookies,
        .solved = solved_cookies != null,
        .error_msg = null,
    };
}

fn cdpHandshake(self: *ChromeDelegator, sock: posix.socket_t) !void {
    _ = self;
    // WebSocket upgrade handshake
    // In a production implementation, this would send a proper HTTP upgrade
    // request with Sec-WebSocket-Key and validate the response. For now,
    // we rely on Chrome's WebSocket endpoint being permissive for localhost
    // connections.
    //
    // A full implementation would:
    // 1. Send: GET /devtools/browser/... HTTP/1.1\r\nUpgrade: websocket\r\n...
    // 2. Read response for 101 Switching Protocols
    // 3. Validate Sec-WebSocket-Accept

    // Minimal WebSocket handshake for Chrome DevTools
    const handshake = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
    _ = posix.write(sock, handshake) catch return error.CdpHandshakeFailed;

    // Read the HTTP 101 response
    var buf: [1024]u8 = undefined;
    const n = posix.read(sock, &buf) catch return error.CdpHandshakeFailed;
    if (n == 0) return error.CdpHandshakeFailed;

    // Check for 101 Switching Protocols
    if (std.mem.indexOf(u8, buf[0..n], "101") == null) {
        return error.CdpHandshakeFailed;
    }
}

fn cdpExecuteChallenge(
    self: *ChromeDelegator,
    sock: posix.socket_t,
    url: []const u8,
    challenge_type: Detector.ChallengeType,
) !?[]const u8 {
    // Send CDP Page.navigate command
    const navigate_cmd = try std.fmt.allocPrint(
        self.allocator,
        "{{\"id\":1,\"method\":\"Page.navigate\",\"params\":{{\"url\":\"{s}\"}}}}",
        .{url},
    );
    defer self.allocator.free(navigate_cmd);

    try self.cdpSendCommand(sock, 1, navigate_cmd);

    // Wait for the challenge to be solved
    // Kasada PoW typically takes 2-5 seconds
    // DataDome WASM challenge typically takes 1-3 seconds
    const wait_time_ns: u64 = switch (challenge_type) {
        .kasada => 8 * std.time.ns_per_s, // Kasada can be slow
        .datadome => 5 * std.time.ns_per_s,
        .none => 3 * std.time.ns_per_s,
    };

    // Poll for completion with a timeout
    var elapsed: u64 = 0;
    const poll_interval_ns: u64 = 500 * std.time.ns_per_ms;

    while (elapsed < wait_time_ns) {
        std.Thread.sleep(poll_interval_ns);
        elapsed += poll_interval_ns;

        // Check if the page has loaded and the challenge is resolved
        if (try self.cdpCheckPageLoaded(sock)) {
            break;
        }
    }

    // Extract cookies from Chrome's cookie store
    const cookies = try self.cdpGetCookies(sock);
    if (cookies) |c| {
        log.info(.http, "Chrome solved challenge, extracted cookies", .{
            .url = url,
            .cookie_len = c.len,
        });
    }

    return cookies;
}

fn cdpSendCommand(self: *ChromeDelegator, sock: posix.socket_t, _: u32, payload: []const u8) !void {
    // Wrap payload in a WebSocket frame (opcode text, masked for client-to-server)
    const frame_header = [_]u8{
        0x81, // FIN + TEXT opcode
        @intCast(payload.len | 0x80), // MASK bit set (client must mask)
        0x12, 0x34, 0x56, 0x78, // Masking key
    };

    // Apply masking
    var masked: std.ArrayList(u8) = .empty;
    defer masked.deinit(self.allocator);

    try masked.appendSlice(self.allocator, &frame_header);
    for (payload, 0..) |byte, i| {
        try masked.append(self.allocator, byte ^ frame_header[4 + (i % 4)]);
    }

    _ = posix.write(sock, masked.items) catch return error.CdpWriteFailed;
}

fn cdpCheckPageLoaded(_: *ChromeDelegator, sock: posix.socket_t) !bool {
    // Read pending WebSocket frames from Chrome
    var buf: [4096]u8 = undefined;
    const n = posix.read(sock, &buf) catch |err| switch (err) {
        error.WouldBlock => return false,
        else => return false,
    };

    if (n == 0) return false;

    // Look for Page.loadEventFired or Page.frameStoppedLoading events
    const content = buf[0..n];
    if (std.mem.indexOf(u8, content, "Page.loadEventFired") != null or
        std.mem.indexOf(u8, content, "Page.frameStoppedLoading") != null or
        std.mem.indexOf(u8, content, "\"method\":\"Page.loadEventFired\"") != null or
        std.mem.indexOf(u8, content, "\"method\":\"Page.frameStoppedLoading\"") != null)
    {
        return true;
    }

    return false;
}

fn cdpGetCookies(self: *ChromeDelegator, sock: posix.socket_t) !?[]const u8 {
    // Send Network.getAllCookies command
    const cmd = "{\"id\":2,\"method\":\"Network.getAllCookies\",\"params\":{}}";
    try self.cdpSendCommand(sock, 2, cmd);

    // Read response
    var buf: [65536]u8 = undefined;

    // Try to read with retries
    var attempts: u8 = 0;
    while (attempts < 10) : (attempts += 1) {
        const n = posix.read(sock, &buf) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(100 * std.time.ns_per_ms);
                continue;
            },
            else => return null,
        };

        if (n == 0) return null;

        const content = buf[0..n];

        // Look for the cookies in the response
        // The response will contain "cookies":[...] in the result
        if (std.mem.indexOf(u8, content, "\"cookies\"")) |cookies_start| {
            // Extract the cookies array — simplified parsing
            // In production, use a proper JSON parser
            const rest = content[cookies_start..];
            if (std.mem.indexOfScalar(u8, rest, '[')) |arr_start| {
                const arr_offset = cookies_start + arr_start;
                if (findMatchingBracket(content, arr_offset)) |arr_end| {
                    const cookies_json = content[arr_offset .. arr_end + 1];
                    return try self.allocator.dupe(u8, cookies_json);
                }
            }
        }

        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    return null;
}

fn findMatchingBracket(content: []const u8, start: usize) ?usize {
    if (start >= content.len or content[start] != '[') return null;

    var depth: u32 = 0;
    var i = start;
    while (i < content.len) : (i += 1) {
        switch (content[i]) {
            '[' => depth += 1,
            ']' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            '"' => {
                // Skip string content (handle escaped quotes)
                i += 1;
                while (i < content.len and content[i] != '"') {
                    if (content[i] == '\\') i += 1; // skip escaped char
                    i += 1;
                }
            },
            else => {},
        }
    }
    return null;
}
