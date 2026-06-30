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
const Cors = @import("Cors.zig");
const AbortSignal = @import("../AbortSignal.zig");
const DOMException = @import("../DOMException.zig");

const log = lp.log;
const Execution = js.Execution;
const IS_DEBUG = @import("builtin").mode == .Debug;

const Fetch = @This();

_exec: *const Execution,
_url: [:0]const u8,
_buf: std.ArrayList(u8),
_response: *Response,
_resolver: js.PromiseResolver.Global,
_owns_response: bool,
_signal: ?*AbortSignal,
_mode: Request.Mode,
_credentials: Request.Credentials,
_method: HttpClient.Method,
_request_headers: ?*Headers,
_body: ?[]const u8,
_request_origin: []const u8,
_preflight_header_names: []const []const u8,

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
    const request_origin = URL.getOrigin(response._arena, exec.url.*) catch null;
    const request_origin_value = request_origin orelse "null";
    fetch.* = .{
        ._exec = exec,
        ._buf = .empty,
        ._url = try response._arena.dupeZ(u8, request._url),
        ._resolver = try resolver.persist(),
        ._response = response,
        ._owns_response = true,
        ._signal = request._signal,
        ._mode = request._mode,
        ._credentials = request._credentials,
        ._method = request._method,
        ._request_headers = request._headers,
        ._body = if (request._body) |body| try response._arena.dupe(u8, body) else null,
        ._request_origin = request_origin_value,
        ._preflight_header_names = &.{},
    };

    const request_is_cross_origin = !exec.isSameOrigin(request._url);
    if (request._mode == .@"same-origin" and !exec.isSameOrigin(request._url)) {
        response._http_response = null;
        response.deinit(exec.page);
        resolver.rejectError("fetch same-origin mode rejected cross-origin URL", .{ .type_error = "fetch error" });
        return resolver.promise();
    }

    if (request._mode == .cors and request_is_cross_origin) {
        fetch._preflight_header_names = try Cors.unsafeRequestHeaderNames(request._headers, response._arena);
        if (!Cors.isSafelistedMethod(request._method) or fetch._preflight_header_names.len > 0) {
            try fetch.startPreflightRequest();
            return resolver.promise();
        }
    }

    try fetch.startFetchRequest();
    return resolver.promise();
}

fn startFetchRequest(self: *Fetch) !void {
    const exec = self._exec;
    const session = exec.session;
    const http_client = &session.browser.http_client;
    var headers = try http_client.newHeadersForUrl(self._url);
    if (self._request_headers) |h| {
        if (self._mode == .@"no-cors") {
            try Cors.populateNoCorsSafelistedHttpHeaders(h, self._response._arena, &headers);
        } else {
            try h.populateHttpHeader(self._response._arena, &headers);
        }
    }
    try exec.headersForRequest(&headers, self._response._arena, self._url);

    const request_is_cross_origin = !exec.isSameOrigin(self._url);
    try Cors.populateFetchMetadataHeaders(
        &headers,
        self._response._arena,
        self._request_origin,
        self._url,
        @tagName(self._mode),
        "empty",
        request_is_cross_origin,
    );

    if (comptime IS_DEBUG) {
        log.debug(.http, "fetch", .{ .url = self._url });
    }

    const cookie_jar = switch (self._credentials) {
        .omit => null,
        .include => &session.cookie_jar,
        .@"same-origin" => if (!request_is_cross_origin) &session.cookie_jar else null,
    };

    // Synchronous failures from request layers (e.g. RobotsLayer returning
    // RobotsBlocked when robots.txt is already cached) are dispatched to
    // httpErrorCallback by Client.request, which rejects the promise and
    // releases response._arena. Propagating the error from here would also
    // fire the `errdefer response.deinit` above and double-free the arena.
    exec.makeRequest(.{
        .ctx = self,
        .url = self._url,
        .method = self._method,
        .frame_id = exec.frameId(),
        .loader_id = exec.loaderId(),
        .body = self._body,
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
}

fn startPreflightRequest(self: *Fetch) !void {
    const exec = self._exec;
    const session = exec.session;
    const http_client = &session.browser.http_client;
    var headers = try http_client.newHeaders();
    try Cors.populatePreflightHttpHeaders(
        &headers,
        self._response._arena,
        self._request_origin,
        self._url,
        self._method,
        self._preflight_header_names,
    );

    if (comptime IS_DEBUG) {
        log.debug(.http, "fetch preflight", .{ .url = self._url });
    }

    exec.makeRequest(.{
        .ctx = self,
        .url = self._url,
        .method = .OPTIONS,
        .frame_id = exec.frameId(),
        .loader_id = exec.loaderId(),
        .body = null,
        .headers = headers,
        .resource_type = .preflight,
        .cookie_jar = null,
        .cookie_origin = exec.url.*,
        .notification = session.notification,
        .start_callback = preflightStartCallback,
        .header_callback = preflightHeaderDoneCallback,
        .data_callback = preflightDataCallback,
        .done_callback = preflightDoneCallback,
        .error_callback = preflightErrorCallback,
        .shutdown_callback = httpShutdownCallback,
    }) catch {};
}

fn preflightStartCallback(response: HttpClient.Response) !void {
    const self: *Fetch = @ptrCast(@alignCast(response.ctx));
    if (comptime IS_DEBUG) {
        log.debug(.http, "preflight start", .{ .url = self._url, .source = "fetch" });
    }
}

fn preflightHeaderDoneCallback(response: HttpClient.Response) !HttpClient.HeaderResult {
    const self: *Fetch = @ptrCast(@alignCast(response.ctx));

    if (self._signal) |signal| {
        if (signal._aborted) {
            return .abort;
        }
    }

    var response_header_iter = response.headerIterator();
    const response_headers = (try response_header_iter.collect(self._response._arena)).items;
    if (!Cors.preflightAllows(
        response.status(),
        response_headers,
        self._method,
        self._preflight_header_names,
        self._request_origin,
        self._credentials == .include,
    )) {
        return rejectHeaderFetch(self, "fetch CORS preflight failed");
    }
    return .proceed;
}

fn preflightDataCallback(_: HttpClient.Response, _: []const u8) !void {}

fn preflightDoneCallback(ctx: *anyopaque) !void {
    const self: *Fetch = @ptrCast(@alignCast(ctx));
    self.startFetchRequest() catch |err| {
        httpErrorCallback(ctx, err);
    };
}

fn preflightErrorCallback(ctx: *anyopaque, err: anyerror) void {
    const self: *Fetch = @ptrCast(@alignCast(ctx));
    log.info(.http, "preflight error", .{
        .source = "fetch",
        .url = self._url,
        .err = err,
    });
    httpErrorCallback(ctx, err);
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
    const is_same_origin = Cors.sameOrigin(requesting_origin, response_origin);

    if (is_same_origin) {
        res._type = .basic;
    } else if (self._mode == .@"no-cors") {
        res._type = .@"opaque";
        res._status = 0;
        res._status_text = "";
        res._url = "";
        res._is_redirected = false;
        return .proceed;
    }

    var response_header_iter = response.headerIterator();
    const response_headers = (try response_header_iter.collect(arena)).items;

    if (res._type != .basic and !Cors.responseAllows(response_headers, requesting_origin orelse "null", self._credentials == .include)) {
        return rejectHeaderFetch(self, "fetch CORS check failed");
    }
    if (!is_same_origin) {
        res._type = .cors;
    }

    for (response_headers) |hdr| {
        if (res._type == .cors and !Cors.isExposedResponseHeader(response_headers, hdr.name, self._credentials == .include)) {
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
    try testing.htmlRunner("net/fetch_cors_preflight_success.html", .{});
    try testing.htmlRunner("net/fetch_cors_preflight_required.html", .{});
    try testing.htmlRunner("net/fetch_hash_route.html", .{});
}
