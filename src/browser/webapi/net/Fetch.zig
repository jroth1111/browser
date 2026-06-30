// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
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
const lp = @import("lightpanda");
const HttpClient = @import("../../HttpClient.zig");

const js = @import("../../js/js.zig");
const URL = @import("../../URL.zig");

const Request = @import("Request.zig");
const Response = @import("Response.zig");
const Headers = @import("Headers.zig");
const AbortSignal = @import("../AbortSignal.zig");
const DOMException = @import("../DOMException.zig");

const log = lp.log;
const Execution = js.Execution;
const IS_DEBUG = @import("builtin").mode == .Debug;

const Fetch = @This();

_exec: *const Execution,
_url: []const u8,
_buf: std.ArrayList(u8),
_response: *Response,
_resolver: js.PromiseResolver.Global,
_owns_response: bool,
_signal: ?*AbortSignal,
_mode: Request.Mode,
_credentials: Request.Credentials,

pub const Input = Request.Input;
pub const InitOpts = Request.InitOpts;

pub fn init(input: Input, options: ?InitOpts, exec: *const Execution) !js.Promise {
    const resolver = exec.js.local.?.createPromiseResolver();

    // A bad RequestInit (e.g. an invalid priority) must reject the promise,
    // not throw synchronously.
    const request = Request.init(input, options, exec) catch {
        resolver.rejectError("fetch init error", .{ .type_error = "Failed to construct Request" });
        return resolver.promise();
    };

    if (request._signal) |signal| {
        if (signal._aborted) {
            resolver.reject("fetch aborted", DOMException.initStatic("The operation was aborted.", "AbortError"));
            return resolver.promise();
        }
    }

    const response = try Response.init(null, .{ .status = 0 }, exec);
    errdefer response.deinit(exec.page);

    const fetch = try response._arena.create(Fetch);
    fetch.* = .{
        ._exec = exec,
        ._buf = .empty,
        ._url = try response._arena.dupe(u8, request._url),
        ._resolver = try resolver.persist(),
        ._response = response,
        ._owns_response = true,
        ._signal = request._signal,
        ._mode = request._mode,
        ._credentials = request._credentials,
    };

    const session = exec.session;
    const http_client = &session.browser.http_client;
    var headers = try http_client.newHeaders();
    if (request._headers) |h| {
        if (request._mode == .@"no-cors") {
            try populateNoCorsSafelistedHttpHeaders(h, exec.call_arena, &headers);
        } else {
            try h.populateHttpHeader(exec.call_arena, &headers);
        }
    }
    try exec.headersForRequest(&headers);

    if (request._mode == .@"same-origin" and !exec.isSameOrigin(request._url)) {
        response._http_response = null;
        response.deinit(exec.page);
        resolver.rejectError("fetch same-origin mode rejected cross-origin URL", .{ .type_error = "fetch error" });
        return resolver.promise();
    }

    const request_origin = URL.getOrigin(exec.call_arena, exec.url.*) catch null;
    const request_origin_value = request_origin orelse "null";
    if (!exec.isSameOrigin(request._url)) {
        if (request._headers == null or !request._headers.?.has("origin", exec)) {
            const origin_header = try std.fmt.allocPrintSentinel(exec.call_arena, "Origin: {s}", .{request_origin_value}, 0);
            try headers.set(origin_header.ptr);
        }
    }
    if (request._headers == null or !request._headers.?.has("sec-fetch-mode", exec)) {
        const mode_header = try std.fmt.allocPrintSentinel(exec.call_arena, "Sec-Fetch-Mode: {s}", .{@tagName(request._mode)}, 0);
        try headers.set(mode_header.ptr);
    }

    if (comptime IS_DEBUG) {
        log.debug(.http, "fetch", .{ .url = request._url });
    }

    const cookie_jar = switch (request._credentials) {
        .omit => null,
        .include => &session.cookie_jar,
        .@"same-origin" => if (exec.isSameOrigin(request._url)) &session.cookie_jar else null,
    };

    // Synchronous failures from request layers (e.g. RobotsLayer returning
    // RobotsBlocked when robots.txt is already cached) are dispatched to
    // httpErrorCallback by Client.request, which rejects the promise and
    // releases response._arena. Propagating the error from here would also
    // fire the `errdefer response.deinit` above and double-free the arena.
    exec.makeRequest(.{
        .ctx = fetch,
        .url = request._url,
        .method = request._method,
        .frame_id = exec.frameId(),
        .loader_id = exec.loaderId(),
        .body = request._body,
        .headers = headers,
        .resource_type = .fetch,
        .cookie_jar = cookie_jar,
        .cookie_origin = exec.url.*,
        .notification = session.notification,
        .start_callback = httpStartCallback,
        .header_callback = httpHeaderDoneCallback,
        .data_callback = httpDataCallback,
        .done_callback = httpDoneCallback,
        .error_callback = httpErrorCallback,
        .shutdown_callback = httpShutdownCallback,
    }) catch {};
    return resolver.promise();
}

fn sameOrigin(requesting_origin: ?[]const u8, response_origin: ?[]const u8) bool {
    const ro = response_origin orelse return true;
    const qo = requesting_origin orelse return false;
    return std.mem.eql(u8, qo, ro);
}

fn responseHeaderValue(response: HttpClient.Response, name: []const u8) ?[]const u8 {
    var it = response.headerIterator();
    while (it.next()) |hdr| {
        if (std.ascii.eqlIgnoreCase(hdr.name, name)) {
            return std.mem.trim(u8, hdr.value, " \t");
        }
    }
    return null;
}

fn isCorsUnsafeRequestHeaderByte(byte: u8) bool {
    return switch (byte) {
        0x00...0x08, 0x0A...0x1F, 0x7F, '"', '(', ')', ':', '<', '>', '?', '@', '[', '\\', ']', '{', '}' => true,
        else => false,
    };
}

fn isCorsSafelistedLanguageValue(value: []const u8) bool {
    if (value.len > 128) {
        return false;
    }
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte)) {
            continue;
        }
        switch (byte) {
            ' ', '*', ',', '-', '.', ';', '=' => {},
            else => return false,
        }
    }
    return true;
}

fn isCorsSafelistedValue(value: []const u8) bool {
    if (value.len > 128) {
        return false;
    }
    for (value) |byte| {
        if (isCorsUnsafeRequestHeaderByte(byte)) {
            return false;
        }
    }
    return true;
}

fn isCorsSafelistedContentType(value: []const u8) bool {
    if (!isCorsSafelistedValue(value)) {
        return false;
    }
    const semicolon = std.mem.indexOfScalar(u8, value, ';') orelse value.len;
    const essence = std.mem.trim(u8, value[0..semicolon], " \t");
    return std.ascii.eqlIgnoreCase(essence, "application/x-www-form-urlencoded") or
        std.ascii.eqlIgnoreCase(essence, "multipart/form-data") or
        std.ascii.eqlIgnoreCase(essence, "text/plain");
}

fn isNoCorsSafelistedRequestHeader(name: []const u8, value: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(name, "accept")) {
        return isCorsSafelistedValue(value);
    }
    if (std.ascii.eqlIgnoreCase(name, "accept-language") or
        std.ascii.eqlIgnoreCase(name, "content-language"))
    {
        return isCorsSafelistedLanguageValue(value);
    }
    if (std.ascii.eqlIgnoreCase(name, "content-type")) {
        return isCorsSafelistedContentType(value);
    }
    return false;
}

fn populateNoCorsSafelistedHttpHeaders(
    request_headers: *Headers,
    allocator: std.mem.Allocator,
    http_headers: *HttpClient.Headers,
) !void {
    const pairs = try request_headers.snapshotPairs(allocator);
    for (pairs) |pair| {
        if (!isNoCorsSafelistedRequestHeader(pair[0], pair[1])) {
            continue;
        }
        const merged = try std.mem.concatWithSentinel(allocator, u8, &.{ pair[0], ": ", pair[1] }, 0);
        try http_headers.set(merged);
    }
}

fn responseAllowsCors(response: HttpClient.Response, requesting_origin: []const u8, credentials: Request.Credentials) bool {
    const allow_origin = responseHeaderValue(response, "access-control-allow-origin") orelse return false;
    const allow_credentials = responseHeaderValue(response, "access-control-allow-credentials") orelse "";

    if (std.mem.eql(u8, allow_origin, "*")) {
        return credentials != .include;
    }
    if (!std.mem.eql(u8, allow_origin, requesting_origin)) {
        return false;
    }
    if (credentials == .include and !std.ascii.eqlIgnoreCase(allow_credentials, "true")) {
        return false;
    }
    return true;
}

fn headerListContains(list: []const u8, name: []const u8, allow_wildcard: bool) bool {
    var it = std.mem.splitScalar(u8, list, ',');
    while (it.next()) |raw| {
        const item = std.mem.trim(u8, raw, " \t");
        if (std.mem.eql(u8, item, "*")) {
            if (allow_wildcard or std.mem.eql(u8, name, "*")) {
                return true;
            }
            continue;
        }
        if (std.ascii.eqlIgnoreCase(item, name)) {
            return true;
        }
    }
    return false;
}

fn isCorsSafelistedResponseHeader(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "cache-control") or
        std.ascii.eqlIgnoreCase(name, "content-language") or
        std.ascii.eqlIgnoreCase(name, "content-length") or
        std.ascii.eqlIgnoreCase(name, "content-type") or
        std.ascii.eqlIgnoreCase(name, "expires") or
        std.ascii.eqlIgnoreCase(name, "last-modified") or
        std.ascii.eqlIgnoreCase(name, "pragma");
}

fn isCorsExposedResponseHeader(response: HttpClient.Response, name: []const u8, credentials: Request.Credentials) bool {
    if (isCorsSafelistedResponseHeader(name)) {
        return true;
    }
    const exposed = responseHeaderValue(response, "access-control-expose-headers") orelse return false;
    return headerListContains(exposed, name, credentials != .include);
}

fn rejectHeaderFetch(self: *Fetch, comptime message: []const u8) HttpClient.HeaderResult {
    var response = self._response;
    response._http_response = null;

    const exec = self._exec;
    const resolver = self._resolver;
    const owns_response = self._owns_response;
    self._owns_response = false;

    var ls: js.Local.Scope = undefined;
    exec.js.localScope(&ls);
    defer ls.deinit();

    ls.toLocal(resolver).rejectError(message, .{ .type_error = "fetch error" });
    if (owns_response) {
        response.deinit(exec.page);
    }
    return .handled;
}

fn httpStartCallback(response: HttpClient.Response) !void {
    const self: *Fetch = @ptrCast(@alignCast(response.ctx));
    if (comptime IS_DEBUG) {
        log.debug(.http, "request start", .{ .url = self._url, .source = "fetch" });
    }
    self._response._http_response = response;
}

fn httpHeaderDoneCallback(response: HttpClient.Response) !HttpClient.HeaderResult {
    const self: *Fetch = @ptrCast(@alignCast(response.ctx));

    if (self._signal) |signal| {
        if (signal._aborted) {
            return .abort;
        }
    }

    const arena = self._response._arena;
    if (response.contentLength()) |cl| {
        try self._buf.ensureTotalCapacity(arena, cl);
    }

    const res = self._response;

    if (comptime IS_DEBUG) {
        log.debug(.http, "request header", .{
            .source = "fetch",
            .url = self._url,
            .status = response.status(),
        });
    }

    res._status = response.status().?;
    res._status_text = std.http.Status.phrase(@enumFromInt(response.status().?)) orelse "";
    res._url = try arena.dupeZ(u8, response.url());
    res._is_redirected = response.redirectCount().? > 0;

    // Determine response type based on origin comparison and Fetch mode.
    const exec = self._exec;
    const requesting_origin = URL.getOrigin(arena, exec.url.*) catch null;
    const response_origin = URL.getOrigin(arena, res._url) catch null;
    const is_same_origin = sameOrigin(requesting_origin, response_origin);

    if (is_same_origin) {
        res._type = .basic;
    } else if (self._mode == .@"no-cors") {
        res._type = .@"opaque";
        res._status = 0;
        res._status_text = "";
        res._url = "";
        res._is_redirected = false;
        return .proceed;
    } else if (!responseAllowsCors(response, requesting_origin orelse "null", self._credentials)) {
        return rejectHeaderFetch(self, "fetch CORS check failed");
    } else {
        res._type = .cors;
    }

    var it = response.headerIterator();
    while (it.next()) |hdr| {
        if (res._type == .cors and !isCorsExposedResponseHeader(response, hdr.name, self._credentials)) {
            continue;
        }
        try res._headers.append(hdr.name, hdr.value, exec);
    }

    return .proceed;
}

fn httpDataCallback(response: HttpClient.Response, data: []const u8) !void {
    const self: *Fetch = @ptrCast(@alignCast(response.ctx));

    // Check if aborted
    if (self._signal) |signal| {
        if (signal._aborted) {
            return error.Abort;
        }
    }

    if (self._response._type == .@"opaque") {
        return;
    }

    try self._buf.appendSlice(self._response._arena, data);
}

fn httpDoneCallback(ctx: *anyopaque) !void {
    const self: *Fetch = @ptrCast(@alignCast(ctx));
    var response = self._response;
    response._http_response = null;
    response._body = if (response._type == .@"opaque")
        .empty
    else
        .{ .bytes = self._buf.items };

    log.info(.http, "request complete", .{
        .source = "fetch",
        .url = self._url,
        .status = response._status,
        .len = self._buf.items.len,
    });

    var ls: js.Local.Scope = undefined;
    self._exec.js.localScope(&ls);
    defer ls.deinit();

    const js_val = try ls.local.zigValueToJs(self._response, .{});
    self._owns_response = false;
    return ls.toLocal(self._resolver).resolve("fetch done", js_val);
}

fn httpErrorCallback(ctx: *anyopaque, err: anyerror) void {
    const self: *Fetch = @ptrCast(@alignCast(ctx));

    log.info(.http, "request error", .{
        .source = "fetch",
        .url = self._url,
        .status = self._response._status,
        .err = err,
    });

    var response = self._response;
    response._http_response = null;

    // Capture this before we reject. Rejection could trigger httpShutdownCallback
    // (via a microtask callback). But if we're here, then we'll take care of
    // cleaning up when we're done.
    const owns_response = self._owns_response;
    self._owns_response = false;

    // the response is only passed on v8 on success, if we're here, it's safe to
    // clear this. (defer since `self is in the response's arena).

    defer if (owns_response) {
        response.deinit(self._exec.page);
    };

    var ls: js.Local.Scope = undefined;
    self._exec.js.localScope(&ls);
    defer ls.deinit();

    // fetch() must reject with a TypeError on network errors per spec
    ls.toLocal(self._resolver).rejectError("fetch error", .{ .type_error = "fetch error" });
}

fn httpShutdownCallback(ctx: *anyopaque) void {
    const self: *Fetch = @ptrCast(@alignCast(ctx));

    if (self._owns_response) {
        var response = self._response;
        response._http_response = null;
        response.deinit(self._exec.page);
        // Do not access `self` after this point: the Fetch struct was
        // allocated from response._arena which has been released.
    }
}

const testing = @import("../../../testing.zig");
test "WebApi: fetch" {
    try testing.htmlRunner("net/fetch.html", .{});
    try testing.htmlRunner("net/fetch_same_origin_mode.html", .{});
    try testing.htmlRunner("net/fetch_cors_allowed.html", .{});
    try testing.htmlRunner("net/fetch_cors_blocked.html", .{});
    try testing.htmlRunner("net/fetch_no_cors_opaque.html", .{});
    try testing.htmlRunner("net/fetch_no_cors_headers.html", .{});
    try testing.htmlRunner("net/fetch_cors_credentials_wildcard.html", .{});
    try testing.htmlRunner("net/fetch_hash_route.html", .{});
}
