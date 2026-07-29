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
const builtin = @import("builtin");

const Config = @import("../Config.zig");

const Allocator = std.mem.Allocator;
const posix = std.posix;

const ChallengerPool = @This();

/// A single Chrome DevTools WebSocket endpoint managed by the pool.
pub const ChromeEndpoint = struct {
    ws_url: std.ArrayList(u8),
    pid: posix.pid_t,
    last_used: i64,
    in_use: bool,
    child: std.process.Child,

    pub fn deinit(self: *ChromeEndpoint, allocator: Allocator) void {
        self.ws_url.deinit(allocator);
    }
};

allocator: Allocator,
endpoints: std.ArrayList(ChromeEndpoint),
mutex: std.Thread.Mutex,
max_pool_size: u8,
chrome_path: []const u8,
idle_timeout_ns: u64,

/// Time an idle Chrome instance stays alive before being killed (5 minutes).
const IDLE_TIMEOUT_NS: u64 = 5 * 60 * std.time.ns_per_s;

pub fn init(allocator: Allocator, config: *const Config) !ChallengerPool {
    const chrome_path = config.chromePath() orelse blk: {
        // Try common Chrome locations
        const candidates = &[_][]const u8{
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/bin/chromium-browser",
            "/usr/bin/chromium",
            "/snap/bin/chromium",
        };
        for (candidates) |path| {
            if (std.fs.accessAbsolute(path, .{})) {
                break :blk path;
            } else |_| {}
        }
        return error.ChromeNotFound;
    };

    return .{
        .allocator = allocator,
        .endpoints = .empty,
        .mutex = .{},
        .max_pool_size = config.chromePoolSize(),
        .chrome_path = chrome_path,
        .idle_timeout_ns = IDLE_TIMEOUT_NS,
    };
}

pub fn deinit(self: *ChallengerPool) void {
    self.killAll();
    self.endpoints.deinit(self.allocator);
}

/// Acquire an available Chrome endpoint from the pool.
/// Returns null if no endpoints are available and the pool is at capacity.
pub fn acquire(self: *ChallengerPool) ?*ChromeEndpoint {
    self.mutex.lock();
    defer self.mutex.unlock();

    // First: try to find an idle endpoint
    for (self.endpoints.items) |*ep| {
        if (!ep.in_use) {
            ep.in_use = true;
            ep.last_used = std.time.timestamp();
            return ep;
        }
    }

    // Second: if pool isn't full, spawn a new Chrome instance
    if (self.endpoints.items.len < self.max_pool_size) {
        const ep = self.spawnChrome() catch |err| {
            log.err(.http, "failed to spawn Chrome for challenge delegation", .{ .err = err });
            return null;
        };
        return ep;
    }

    // Pool is full and all in use
    log.warn(.http, "challenge delegation pool exhausted", .{
        .pool_size = self.endpoints.items.len,
    });
    return null;
}

/// Release a Chrome endpoint back to the pool.
pub fn release(self: *ChallengerPool, endpoint: *ChromeEndpoint) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    endpoint.in_use = false;
    endpoint.last_used = std.time.timestamp();
}

/// Kill all idle Chrome instances that have exceeded the idle timeout.
pub fn killIdle(self: *ChallengerPool) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const now = std.time.timestamp();
    var i: usize = self.endpoints.items.len;
    while (i > 0) {
        i -= 1;
        const ep = &self.endpoints.items[i];
        if (!ep.in_use and (now - ep.last_used) > @as(i64, @intCast(self.idle_timeout_ns / std.time.ns_per_s))) {
            log.info(.http, "killing idle Chrome instance", .{ .pid = ep.pid });
            self.killEndpoint(i);
        }
    }
}

/// Kill all Chrome instances and remove them from the pool.
pub fn killAll(self: *ChallengerPool) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    while (self.endpoints.items.len > 0) {
        self.killEndpoint(self.endpoints.items.len - 1);
    }
}

/// Check the health of all Chrome instances by sending a CDP getVersion call.
/// Removes any dead instances from the pool.
pub fn checkHealth(self: *ChallengerPool) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    var i: usize = self.endpoints.items.len;
    while (i > 0) {
        i -= 1;
        const ep = &self.endpoints.items[i];
        if (ep.in_use) continue;

        if (!self.isAlive(ep)) {
            log.warn(.http, "removing dead Chrome instance from pool", .{ .pid = ep.pid });
            self.killEndpoint(i);
        }
    }
}

fn isAlive(_: *ChallengerPool, endpoint: *ChromeEndpoint) bool {
    // Try to connect to the WebSocket and send a simple CDP command
    const ws_url = endpoint.ws_url.items;

    // Quick check: try to connect via TCP
    const uri = std.Uri.parse(ws_url) catch return false;
    const host_component = uri.host orelse return false;
    var host_buf: [std.Uri.host_name_max]u8 = undefined;
    const host = host_component.toRaw(&host_buf) catch return false;
    const port = uri.port orelse 9222;

    const address = std.net.Address.parseIp(host, port) catch return false;
    const sock = posix.socket(address.any.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, posix.IPPROTO.TCP) catch return false;
    defer posix.close(sock);

    // Set a short timeout for the health check
    const timeout: posix.timeval = .{ .sec = 2, .usec = 0 };
    posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout)) catch {};
    posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.SNDTIMEO, std.mem.asBytes(&timeout)) catch {};

    posix.connect(sock, &address.any, address.getOsSockLen()) catch return false;

    // Connection succeeded — the Chrome process is likely alive
    return true;
}

fn spawnChrome(self: *ChallengerPool) !*ChromeEndpoint {
    // Spawn Chrome with --remote-debugging-port=0 to let OS assign a free port.
    // Chrome prints the WebSocket URL to stderr.
    var child = std.process.Child.init(
        &[_][]const u8{
            self.chrome_path,
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            "--disable-dev-shm-usage",
            "--disable-extensions",
            "--disable-background-networking",
            "--remote-debugging-port=0",
            "--remote-debugging-address=127.0.0.1",
            "about:blank",
        },
        self.allocator,
    );

    // Pipe stderr so we can read the DevTools WebSocket URL
    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stdin_behavior = .Close;

    try child.spawn();

    // Read stderr to get the DevTools WebSocket URL
    // Chrome prints: "DevTools listening on ws://127.0.0.1:PORT/devtools/browser/UUID"
    var ws_url_buf: [512]u8 = undefined;
    var ws_url_len: usize = 0;

    // Read from stderr with a timeout
    const stderr = child.stderr.?;
    var read_buf: [256]u8 = undefined;

    // Try to read the WebSocket URL with a timeout
    var attempts: u8 = 0;
    while (attempts < 50) : (attempts += 1) {
        const n = posix.read(stderr.handle, &read_buf) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(100 * std.time.ns_per_ms);
                continue;
            },
            else => {
                log.err(.http, "failed to read Chrome stderr", .{ .err = err });
                _ = child.kill() catch {};
                return error.ChromeSpawnFailed;
            },
        };

        if (n > 0) {
            const end = @min(ws_url_len + n, ws_url_buf.len);
            @memcpy(ws_url_buf[ws_url_len..end], read_buf[0..n]);
            ws_url_len = end;

            // Search for the DevTools URL in what we've read so far
            const content = ws_url_buf[0..ws_url_len];
            if (std.mem.indexOf(u8, content, "DevTools listening on")) |start_offset| {
                const url_start = start_offset + "DevTools listening on ".len;
                if (std.mem.indexOfScalar(u8, content[url_start..], '\n')) |newline| {
                    const url = content[url_start .. url_start + newline];
                    // Trim any trailing \r
                    const trimmed = std.mem.trimRight(u8, url, "\r");

                    var ws_url = std.ArrayList(u8).empty;
                    try ws_url.appendSlice(self.allocator, trimmed);

                    const endpoint = ChromeEndpoint{
                        .ws_url = ws_url,
                        .pid = child.id,
                        .last_used = std.time.timestamp(),
                        .in_use = true,
                        .child = child,
                    };

                    try self.endpoints.append(self.allocator, endpoint);
                    const ep_ptr = &self.endpoints.items[self.endpoints.items.len - 1];

                    log.info(.http, "spawned Chrome for challenge delegation", .{
                        .pid = child.id,
                        .ws_url = trimmed,
                    });

                    return ep_ptr;
                }
            }
        } else {
            // EOF — Chrome exited before printing DevTools URL
            break;
        }

        if (ws_url_len >= ws_url_buf.len) break;
    }

    // Failed to get WebSocket URL
    log.err(.http, "Chrome did not print DevTools URL", .{});
    _ = child.kill() catch {};
    return error.ChromeSpawnFailed;
}

fn killEndpoint(self: *ChallengerPool, index: usize) void {
    var ep = self.endpoints.orderedRemove(index);
    _ = ep.child.kill() catch {};
    // Wait to reap the process
    _ = ep.child.wait() catch {};
    ep.deinit(self.allocator);
}

/// Spawn an initial batch of Chrome instances to fill the pool.
pub fn prewarm(self: *ChallengerPool) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const to_spawn = self.max_pool_size;
    var spawned: u8 = 0;
    while (spawned < to_spawn) : (spawned += 1) {
        _ = self.spawnChrome() catch |err| {
            log.warn(.http, "failed to prewarm Chrome pool", .{
                .err = err,
                .spawned = spawned,
                .target = to_spawn,
            });
            break;
        };
    }

    log.info(.http, "Chrome pool prewarmed", .{
        .pool_size = self.endpoints.items.len,
    });
}
