const std = @import("std");

const HttpClient = @import("../../HttpClient.zig");
const http = @import("../../../network/http.zig");

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
