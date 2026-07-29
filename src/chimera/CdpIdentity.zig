const std = @import("std");

const Authority = @import("Authority.zig");

pub const PROTOCOL_VERSION = "1.3";
pub const REVISION = "@9e6ded5ac1ff5e38d930ae52bd9aec09bd1a68e4";
pub const JS_VERSION = "12.4.254.8";

pub const DEFAULT_CDP_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36";
pub const DEFAULT_CDP_PRODUCT = "Chrome/136.0.7103.59";

pub const DEFAULT_HTTP_BROWSER = "Lightpanda/1.0";
pub const DEFAULT_HTTP_USER_AGENT = "Lightpanda/1.0";

pub const Product = struct {
    value: []const u8,
    owned: bool = false,

    pub fn deinit(self: Product, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.value);
        }
    }
};

pub fn cdpProduct(allocator: std.mem.Allocator, authority: ?*const Authority) !Product {
    const active = authority orelse return .{ .value = DEFAULT_CDP_PRODUCT };
    return chromeProduct(allocator, active.profile.ua_data.ua_full_version);
}

pub fn cdpUserAgent(authority: ?*const Authority) []const u8 {
    const active = authority orelse return DEFAULT_CDP_USER_AGENT;
    return active.profile.headers.user_agent;
}

pub fn httpBrowserProduct(allocator: std.mem.Allocator, authority: ?*const Authority) !Product {
    const active = authority orelse return .{ .value = DEFAULT_HTTP_BROWSER };
    return chromeProduct(allocator, active.profile.ua_data.ua_full_version);
}

pub fn httpUserAgent(authority: ?*const Authority) []const u8 {
    const active = authority orelse return DEFAULT_HTTP_USER_AGENT;
    return active.profile.headers.user_agent;
}

pub fn ownsHeaderName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "user-agent") or
        std.ascii.eqlIgnoreCase(name, "accept-language") or
        startsWithIgnoreCase(name, "sec-ch-ua");
}

fn chromeProduct(allocator: std.mem.Allocator, ua_full_version: []const u8) !Product {
    return .{
        .value = try std.fmt.allocPrint(allocator, "Chrome/{s}", .{ua_full_version}),
        .owned = true,
    };
}

fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
    return value.len >= prefix.len and std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
}

test "cdp identity uses unmanaged fallback without Chimera authority" {
    const testing = std.testing;

    const cdp_product = try cdpProduct(testing.allocator, null);
    defer cdp_product.deinit(testing.allocator);
    try testing.expectEqualStrings(DEFAULT_CDP_PRODUCT, cdp_product.value);
    try testing.expectEqualStrings(DEFAULT_CDP_USER_AGENT, cdpUserAgent(null));

    const http_product = try httpBrowserProduct(testing.allocator, null);
    defer http_product.deinit(testing.allocator);
    try testing.expectEqualStrings(DEFAULT_HTTP_BROWSER, http_product.value);
    try testing.expectEqualStrings(DEFAULT_HTTP_USER_AGENT, httpUserAgent(null));
}

test "cdp identity derives managed profile product and user agent" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const authority = try Authority.parseLeaky(arena.allocator(),
        \\{
        \\  "authority_version":"chimera-lightpanda-authority/v1",
        \\  "profile_schema_version":"chimera-browser-profile/v1",
        \\  "profile_id":"lightpanda:sess-identity",
        \\  "target_domain":"example.com",
        \\  "profile":{
        \\    "schema_version":"chimera-browser-profile/v1",
        \\    "profile_id":"lightpanda:sess-identity",
        \\    "target_domain":"example.com",
        \\    "user_agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
        \\    "app_version":"5.0",
        \\    "accept_language":"en-US,en;q=0.9",
        \\    "languages":["en-US","en"],
        \\    "headers":{
        \\      "User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
        \\      "Accept-Language":"en-US,en;q=0.9",
        \\      "Sec-CH-UA":"\"Chromium\";v=\"136\"",
        \\      "Sec-CH-UA-Mobile":"?0",
        \\      "Sec-CH-UA-Platform":"\"macOS\"",
        \\      "Sec-CH-UA-Full-Version":"\"136.0.0.0\"",
        \\      "Sec-CH-UA-Full-Version-List":"\"Chromium\";v=\"136.0.0.0\"",
        \\      "Sec-CH-UA-Arch":"\"arm\"",
        \\      "Sec-CH-UA-Bitness":"\"64\"",
        \\      "Sec-CH-UA-Model":"\"\"",
        \\      "Sec-CH-UA-Platform-Version":"\"27.0.0\""
        \\    },
        \\    "navigator":{
        \\      "platform":"MacIntel",
        \\      "vendor":"Google Inc.",
        \\      "product":"Gecko",
        \\      "hardware_concurrency":8,
        \\      "device_memory":8,
        \\      "max_touch_points":0,
        \\      "webdriver":false
        \\    },
        \\    "ua_data":{
        \\      "brands":[{"brand":"Chromium","version":"136"}],
        \\      "full_version_list":[{"brand":"Chromium","version":"136.0.0.0"}],
        \\      "mobile":false,
        \\      "platform":"macOS",
        \\      "architecture":"arm",
        \\      "bitness":"64",
        \\      "model":"",
        \\      "platform_version":"27.0.0",
        \\      "ua_full_version":"136.0.0.0",
        \\      "wow64":false,
        \\      "form_factor":["Desktop"]
        \\    },
        \\    "seeds":{
        \\      "canvas":1,
        \\      "audio":2,
        \\      "font":3,
        \\      "human":4
        \\    },
        \\    "plugins":{
        \\      "pdf_enabled":true
        \\    },
        \\    "canvas":{
        \\      "enabled":true,
        \\      "seed":1
        \\    },
        \\    "audio":{
        \\      "enabled":true,
        \\      "seed":2
        \\    },
        \\    "webgl":{
        \\      "enabled":true,
        \\      "vendor":"Google Inc. (Apple)",
        \\      "renderer":"ANGLE (Apple, ANGLE Metal Renderer: Apple M-series, Unspecified Version)"
        \\    },
        \\    "webrtc":{
        \\      "enabled":false,
        \\      "exit_ip":null
        \\    },
        \\    "storage":{
        \\      "quota_bytes":5368709120,
        \\      "usage_bytes":0
        \\    },
        \\    "transport":{
        \\      "impersonate_target":"chrome136",
        \\      "requires_curl_impersonate":true
        \\    },
        \\    "capabilities":{
        \\      "requires_proxy":true,
        \\      "requires_webrtc_exit_ip":false,
        \\      "requires_curl_impersonate":true
        \\    }
        \\  },
        \\  "network":{
        \\    "proxy_url":"http://127.0.0.1:8080",
        \\    "requires_proxy":true
        \\  },
        \\  "diagnostics":{
        \\    "expected_impersonation_target":"chrome136",
        \\    "requires_curl_impersonate":true
        \\  }
        \\}
    );

    const cdp_product = try cdpProduct(testing.allocator, &authority);
    defer cdp_product.deinit(testing.allocator);
    try testing.expectEqualStrings("Chrome/136.0.0.0", cdp_product.value);
    try testing.expectEqualStrings(authority.profile.headers.user_agent, cdpUserAgent(&authority));

    const http_product = try httpBrowserProduct(testing.allocator, &authority);
    defer http_product.deinit(testing.allocator);
    try testing.expectEqualStrings("Chrome/136.0.0.0", http_product.value);
    try testing.expectEqualStrings(authority.profile.headers.user_agent, httpUserAgent(&authority));
}

test "cdp identity owns profile identity header names" {
    const testing = std.testing;

    try testing.expect(ownsHeaderName("User-Agent"));
    try testing.expect(ownsHeaderName("accept-language"));
    try testing.expect(ownsHeaderName("Sec-CH-UA"));
    try testing.expect(ownsHeaderName("sec-ch-ua-full-version-list"));
    try testing.expect(!ownsHeaderName("X-Requested-With"));
    try testing.expect(!ownsHeaderName("Sec-Fetch-Site"));
}
