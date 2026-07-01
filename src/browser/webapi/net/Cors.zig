const std = @import("std");

const HttpClient = @import("../../HttpClient.zig");
const http = @import("../../../network/http.zig");

const Site = @import("../../Site.zig");
const URL = @import("../../URL.zig");
const Headers = @import("Headers.zig");

pub fn sameOrigin(requesting_origin: ?[]const u8, response_origin: ?[]const u8) bool {
    const ro = response_origin orelse return true;
    const qo = requesting_origin orelse return false;
    return std.mem.eql(u8, qo, ro);
}

pub fn responseHeaderValue(headers: []const http.Header, name: []const u8) ?[]const u8 {
    for (headers) |hdr| {
        if (std.ascii.eqlIgnoreCase(hdr.name, name)) {
            return std.mem.trim(u8, hdr.value, " \t");
        }
    }
    return null;
}

fn isUnsafeRequestHeaderByte(byte: u8) bool {
    return switch (byte) {
        0x00...0x08, 0x0A...0x1F, 0x7F, '"', '(', ')', ':', '<', '>', '?', '@', '[', '\\', ']', '{', '}' => true,
        else => false,
    };
}

fn isSafelistedLanguageValue(value: []const u8) bool {
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

fn isSafelistedValue(value: []const u8) bool {
    if (value.len > 128) {
        return false;
    }
    for (value) |byte| {
        if (isUnsafeRequestHeaderByte(byte)) {
            return false;
        }
    }
    return true;
}

pub fn isSafelistedContentType(value: []const u8) bool {
    if (!isSafelistedValue(value)) {
        return false;
    }
    const semicolon = std.mem.indexOfScalar(u8, value, ';') orelse value.len;
    const essence = std.mem.trim(u8, value[0..semicolon], " \t");
    return std.ascii.eqlIgnoreCase(essence, "application/x-www-form-urlencoded") or
        std.ascii.eqlIgnoreCase(essence, "multipart/form-data") or
        std.ascii.eqlIgnoreCase(essence, "text/plain");
}

pub fn isSafelistedMethod(method: http.Method) bool {
    return method == .GET or method == .HEAD or method == .POST;
}

pub fn methodName(method: http.Method) []const u8 {
    return switch (method) {
        .GET => "GET",
        .PUT => "PUT",
        .POST => "POST",
        .DELETE => "DELETE",
        .HEAD => "HEAD",
        .OPTIONS => "OPTIONS",
        .PATCH => "PATCH",
        .PROPFIND => "PROPFIND",
    };
}

pub fn isSafelistedRequestHeader(name: []const u8, value: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(name, "accept")) {
        return isSafelistedValue(value);
    }
    if (std.ascii.eqlIgnoreCase(name, "accept-language") or
        std.ascii.eqlIgnoreCase(name, "content-language"))
    {
        return isSafelistedLanguageValue(value);
    }
    if (std.ascii.eqlIgnoreCase(name, "content-type")) {
        return isSafelistedContentType(value);
    }
    return false;
}

fn hasHeaderName(names: []const []const u8, name: []const u8) bool {
    for (names) |existing| {
        if (std.ascii.eqlIgnoreCase(existing, name)) {
            return true;
        }
    }
    return false;
}

fn lessThanHeaderName(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

pub fn unsafeRequestHeaderNames(
    request_headers: ?*Headers,
    allocator: std.mem.Allocator,
) ![]const []const u8 {
    const headers = request_headers orelse return &.{};
    const pairs = try headers.snapshotPairs(allocator);

    var names: std.ArrayList([]const u8) = .empty;
    for (pairs) |pair| {
        if (isSafelistedRequestHeader(pair[0], pair[1])) {
            continue;
        }
        if (hasHeaderName(names.items, pair[0])) {
            continue;
        }
        const lowered = try allocator.dupe(u8, pair[0]);
        _ = std.ascii.lowerString(lowered, pair[0]);
        try names.append(allocator, lowered);
    }
    std.mem.sort([]const u8, names.items, {}, lessThanHeaderName);
    return try names.toOwnedSlice(allocator);
}

pub fn requestRequiresPreflight(
    method: http.Method,
    request_headers: ?*Headers,
    allocator: std.mem.Allocator,
) !bool {
    if (!isSafelistedMethod(method)) {
        return true;
    }
    const headers = request_headers orelse return false;
    const pairs = try headers.snapshotPairs(allocator);
    for (pairs) |pair| {
        if (!isSafelistedRequestHeader(pair[0], pair[1])) {
            return true;
        }
    }
    return false;
}

pub fn fetchMetadataSite(
    allocator: std.mem.Allocator,
    requesting_origin: []const u8,
    request_url: [:0]const u8,
) ![]const u8 {
    const request_origin = try URL.getOrigin(allocator, request_url) orelse return "cross-site";
    if (std.mem.eql(u8, requesting_origin, request_origin)) {
        return "same-origin";
    }
    if (Site.sameSiteOriginToUrl(requesting_origin, request_url)) {
        return "same-site";
    }
    return "cross-site";
}

pub fn navigationFetchMetadataSite(
    allocator: std.mem.Allocator,
    initiator_url: ?[:0]const u8,
    request_url: [:0]const u8,
) ![]const u8 {
    const url = initiator_url orelse return "none";
    const requesting_origin = try URL.getOrigin(allocator, url) orelse return "cross-site";
    return fetchMetadataSite(allocator, requesting_origin, request_url);
}

fn populateFetchMetadataHeaderValues(
    http_headers: *HttpClient.Headers,
    allocator: std.mem.Allocator,
    mode: []const u8,
    dest: []const u8,
    site: []const u8,
) !void {
    const mode_header = try std.fmt.allocPrintSentinel(allocator, "Sec-Fetch-Mode: {s}", .{mode}, 0);
    try http_headers.set(mode_header.ptr);

    const dest_header = try std.fmt.allocPrintSentinel(allocator, "Sec-Fetch-Dest: {s}", .{dest}, 0);
    try http_headers.set(dest_header.ptr);

    const site_header = try std.fmt.allocPrintSentinel(allocator, "Sec-Fetch-Site: {s}", .{site}, 0);
    try http_headers.set(site_header.ptr);
}

pub fn populateFetchMetadataHeaders(
    http_headers: *HttpClient.Headers,
    allocator: std.mem.Allocator,
    requesting_origin: []const u8,
    request_url: [:0]const u8,
    mode: []const u8,
    dest: []const u8,
    include_origin: bool,
) !void {
    if (include_origin) {
        const origin_header = try std.fmt.allocPrintSentinel(allocator, "Origin: {s}", .{requesting_origin}, 0);
        try http_headers.set(origin_header.ptr);
    }

    try populateFetchMetadataHeaderValues(
        http_headers,
        allocator,
        mode,
        dest,
        try fetchMetadataSite(allocator, requesting_origin, request_url),
    );
}

pub fn populateNavigationFetchMetadataHeaders(
    http_headers: *HttpClient.Headers,
    allocator: std.mem.Allocator,
    initiator_url: ?[:0]const u8,
    request_url: [:0]const u8,
    dest: []const u8,
) !void {
    try populateFetchMetadataHeaderValues(
        http_headers,
        allocator,
        "navigate",
        dest,
        try navigationFetchMetadataSite(allocator, initiator_url, request_url),
    );

    // Chrome only ever sends Sec-Fetch-User on requests it treats as
    // user-activated top-level/sub-frame navigations, never on subresource
    // fetch/XHR/CORS/preflight requests. That is why this is set here, in
    // the navigation-only wrapper, rather than in the shared
    // populateFetchMetadataHeaderValues helper above (which is also used by
    // the non-navigation paths). Every caller of this function represents a
    // real navigation, so the value is unconditionally "?1".
    try http_headers.set("Sec-Fetch-User: ?1");
}

pub fn populatePreflightHttpHeaders(
    http_headers: *HttpClient.Headers,
    allocator: std.mem.Allocator,
    origin: []const u8,
    request_url: [:0]const u8,
    method: http.Method,
    request_header_names: []const []const u8,
) !void {
    try populateFetchMetadataHeaders(http_headers, allocator, origin, request_url, "cors", "empty", true);

    const method_header = try std.fmt.allocPrintSentinel(
        allocator,
        "Access-Control-Request-Method: {s}",
        .{methodName(method)},
        0,
    );
    try http_headers.set(method_header.ptr);

    if (request_header_names.len > 0) {
        const joined = try std.mem.join(allocator, ", ", request_header_names);
        const header = try std.mem.concatWithSentinel(
            allocator,
            u8,
            &.{ "Access-Control-Request-Headers: ", joined },
            0,
        );
        try http_headers.set(header.ptr);
    }
}

pub fn populateNoCorsSafelistedHttpHeaders(
    request_headers: *Headers,
    allocator: std.mem.Allocator,
    http_headers: *HttpClient.Headers,
) !void {
    const pairs = try request_headers.snapshotPairs(allocator);
    for (pairs) |pair| {
        if (!isSafelistedRequestHeader(pair[0], pair[1])) {
            continue;
        }
        const merged = try std.mem.concatWithSentinel(allocator, u8, &.{ pair[0], ": ", pair[1] }, 0);
        try http_headers.set(merged);
    }
}

pub fn responseAllows(headers: []const http.Header, requesting_origin: []const u8, credentials_include: bool) bool {
    const allow_origin = responseHeaderValue(headers, "access-control-allow-origin") orelse return false;
    const allow_credentials = responseHeaderValue(headers, "access-control-allow-credentials") orelse "";

    if (std.mem.eql(u8, allow_origin, "*")) {
        return !credentials_include;
    }
    if (!std.mem.eql(u8, allow_origin, requesting_origin)) {
        return false;
    }
    if (credentials_include and !std.ascii.eqlIgnoreCase(allow_credentials, "true")) {
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

pub fn preflightAllows(
    status: ?u16,
    headers: []const http.Header,
    method: http.Method,
    request_header_names: []const []const u8,
    requesting_origin: []const u8,
    credentials_include: bool,
) bool {
    const code = status orelse return false;
    if (code < 200 or code > 299) {
        return false;
    }

    if (!responseAllows(headers, requesting_origin, credentials_include)) {
        return false;
    }

    if (!isSafelistedMethod(method)) {
        const allow_methods = responseHeaderValue(headers, "access-control-allow-methods") orelse return false;
        if (!headerListContains(allow_methods, methodName(method), !credentials_include)) {
            return false;
        }
    }

    if (request_header_names.len > 0) {
        const allow_headers = responseHeaderValue(headers, "access-control-allow-headers") orelse return false;
        for (request_header_names) |name| {
            if (!headerListContains(allow_headers, name, !credentials_include)) {
                return false;
            }
        }
    }

    return true;
}

pub fn isSafelistedResponseHeader(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "cache-control") or
        std.ascii.eqlIgnoreCase(name, "content-language") or
        std.ascii.eqlIgnoreCase(name, "content-length") or
        std.ascii.eqlIgnoreCase(name, "content-type") or
        std.ascii.eqlIgnoreCase(name, "expires") or
        std.ascii.eqlIgnoreCase(name, "last-modified") or
        std.ascii.eqlIgnoreCase(name, "pragma");
}

pub fn isExposedResponseHeader(headers: []const http.Header, name: []const u8, credentials_include: bool) bool {
    if (isSafelistedResponseHeader(name)) {
        return true;
    }
    const exposed = responseHeaderValue(headers, "access-control-expose-headers") orelse return false;
    return headerListContains(exposed, name, !credentials_include);
}
