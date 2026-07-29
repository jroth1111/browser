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

const http = @import("../http.zig");
const Request = @import("../../browser/HttpClient.zig").Request;
const Transfer = @import("../../browser/HttpClient.zig").Transfer;
const Response = @import("../../browser/HttpClient.zig").Response;
const Layer = @import("../../browser/HttpClient.zig").Layer;
const Forward = @import("Forward.zig");
const HeaderResult = @import("../../browser/HttpClient.zig").HeaderResult;

const ChallengerPool = @import("../../challenger/ChallengerPool.zig");
const ChromeDelegator = @import("../../challenger/ChromeDelegator.zig");
const Detector = @import("../../challenger/Detector.zig");

const ChallengeLayer = @This();

/// Reference to the shared Chrome pool (null when delegation is disabled).
pool: ?*ChallengerPool = null,

next: Layer = undefined,

/// Cached challenge tokens per host, keyed by origin.
/// When a challenge is solved, we store the cookies here and inject them
/// into subsequent requests to the same origin.
token_cache: std.StringHashMapUnmanaged([]const u8) = .empty,
allocator: std.mem.Allocator,

pub fn deinit(self: *ChallengeLayer) void {
    var it = self.token_cache.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.value_ptr.*);
    }
    self.token_cache.deinit(self.allocator);
}

pub fn layer(self: *ChallengeLayer) Layer {
    return .{
        .ptr = self,
        .vtable = &.{
            .request = request,
        },
    };
}

fn request(ptr: *anyopaque, transfer: *Transfer) anyerror!void {
    const self: *ChallengeLayer = @ptrCast(@alignCast(ptr));

    // If no pool is configured, pass through directly
    _ = self.pool orelse {
        return self.next.request(transfer);
    };

    const req = &transfer.req;

    // Check if we have cached tokens for this origin
    const origin = extractOrigin(req.url) orelse {
        return self.next.request(transfer);
    };

    if (self.token_cache.get(origin)) |cookies| {
        // Inject cached challenge cookies
        log.debug(.http, "injecting cached challenge cookies", .{
            .url = req.url,
            .origin = origin,
        });
        try req.headers.set(try std.fmt.allocPrintSentinel(
            self.allocator,
            "Cookie: {s}",
            .{cookies},
            0,
        ));
    }

    // Install response interception wrappers
    const ctx = try transfer.arena.create(ChallengeContext);
    ctx.* = .{
        .layer = self,
        .transfer = transfer,
        .forward = Forward.capture(req),
        .origin = origin,
    };

    // Wrap callbacks to detect challenge responses
    req.ctx = ctx;
    if (ctx.forward.start != null) req.start_callback = ChallengeContext.startCallback;
    req.header_callback = ChallengeContext.headerCallback;
    req.data_callback = ChallengeContext.dataCallback;
    req.done_callback = ChallengeContext.doneCallback;
    req.error_callback = ChallengeContext.errorCallback;
    if (ctx.forward.shutdown != null) req.shutdown_callback = ChallengeContext.shutdownCallback;

    return self.next.request(transfer);
}

/// Extract the origin (scheme + host + port) from a URL for token caching.
fn extractOrigin(url: []const u8) ?[]const u8 {
    // Simple extraction: find "://" then find the next "/" or end
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    const authority_start = scheme_end + 3;
    const authority_end = std.mem.indexOfScalarPos(u8, url, authority_start, '/') orelse url.len;

    // Include scheme for proper origin matching
    return url[0..authority_end];
}

pub const ChallengeContext = struct {
    layer: *ChallengeLayer,
    transfer: *Transfer,
    forward: Forward,
    origin: []const u8,
    status: u16 = 0,
    body_buf: std.ArrayList(u8) = .empty,
    challenge_detected: bool = false,

    fn startCallback(response: Response) anyerror!void {
        const ctx: *ChallengeContext = @ptrCast(@alignCast(response.ctx));
        return ctx.forward.forwardStart(response);
    }

    fn headerCallback(response: Response) anyerror!HeaderResult {
        const ctx: *ChallengeContext = @ptrCast(@alignCast(response.ctx));
        ctx.status = response.status() orelse 0;

        // Check for challenge indicators in headers
        const result = Detector.detectChallenge(ctx.status, response.headerIterator(), null);
        if (result.challenge_type != .none) {
            log.info(.http, "challenge detected in response headers", .{
                .url = ctx.transfer.req.url,
                .type = @tagName(result.challenge_type),
                .confidence = @tagName(result.confidence),
                .status = ctx.status,
            });
            ctx.challenge_detected = true;
        }

        return ctx.forward.forwardHeader(response);
    }

    fn dataCallback(response: Response, chunk: []const u8) anyerror!void {
        const ctx: *ChallengeContext = @ptrCast(@alignCast(response.ctx));

        // Accumulate body for analysis if we haven't detected a challenge yet
        if (!ctx.challenge_detected and ctx.body_buf.capacity > 0) {
            ctx.body_buf.appendSlice(ctx.layer.allocator, chunk) catch {};
        }

        return ctx.forward.forwardData(response, chunk);
    }

    fn doneCallback(ptr: *anyopaque) anyerror!void {
        const ctx: *ChallengeContext = @ptrCast(@alignCast(ptr));

        // If we detected a challenge and have a pool, delegate to Chrome
        if (ctx.challenge_detected and ctx.layer.pool != null) {
            ctx.handleChallenge();
        }

        defer ctx.body_buf.deinit(ctx.layer.allocator);
        return ctx.forward.forwardDone();
    }

    fn errorCallback(ptr: *anyopaque, err: anyerror) void {
        const ctx: *ChallengeContext = @ptrCast(@alignCast(ptr));
        ctx.body_buf.deinit(ctx.layer.allocator);
        ctx.forward.forwardErr(err);
    }

    fn shutdownCallback(ptr: *anyopaque) void {
        const ctx: *ChallengeContext = @ptrCast(@alignCast(ptr));
        ctx.body_buf.deinit(ctx.layer.allocator);
        ctx.forward.forwardShutdown();
    }

    fn handleChallenge(self: *ChallengeContext) void {
        const pool = self.layer.pool orelse return;
        const body = if (self.body_buf.items.len > 0) self.body_buf.items else null;

        const empty_headers = [_]http.Header{.{
            .name = "set-cookie",
            .value = "",
        }};
        const result = Detector.detectChallenge(self.status, .{ .list = .{ .list = &empty_headers } }, body);

        if (result.challenge_type == .none) return;

        // Delegate to Chrome
        var delegator = ChromeDelegator.init(self.layer.allocator, pool);
        var delegation_result = delegator.solveChallenge(
            self.transfer.req.url,
            result.challenge_type,
            null, // proxy — would come from config
        ) catch |err| {
            log.err(.http, "challenge delegation failed", .{
                .url = self.transfer.req.url,
                .err = err,
            });
            return;
        };
        defer delegation_result.deinit(self.layer.allocator);

        if (delegation_result.solved) {
            if (delegation_result.solved_cookies) |cookies| {
                // Cache the solved cookies for this origin
                const cached = self.layer.allocator.dupe(u8, cookies) catch return;
                const prev = self.layer.token_cache.fetchPut(self.layer.allocator, self.origin, cached) catch {
                    self.layer.allocator.free(cached);
                    return;
                };
                if (prev) |old| {
                    self.layer.allocator.free(old.value);
                }

                log.info(.http, "challenge solved, cookies cached", .{
                    .origin = self.origin,
                    .cookie_len = cookies.len,
                });
            }
        } else if (delegation_result.error_msg) |msg| {
            log.warn(.http, "challenge delegation error", .{
                .url = self.transfer.req.url,
                .err_msg = msg,
            });
        }
    }
};
