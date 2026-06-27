const std = @import("std");

const Profile = @import("Profile.zig");

pub const VERSION = "chimera-lightpanda-authority/v1";

const Authority = @This();

authority_version: []const u8,
profile_schema_version: []const u8,
profile_id: []const u8,
target_domain: []const u8,
profile: Profile,
network: Network,
diagnostics: Diagnostics,

pub const Network = struct {
    proxy_url: []const u8,
    route_id: ?[]const u8 = null,
    proxy_route: ?[]const u8 = null,
    requires_proxy: bool = true,
};

pub const Diagnostics = struct {
    expected_impersonation_target: ?[]const u8 = null,
    requires_curl_impersonate: bool = false,
};

pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Authority {
    const bytes = try std.fs.cwd().readFileAllocOptions(allocator, path, 1024 * 1024, null, .of(u8), null);
    return parseLeaky(allocator, bytes);
}

pub fn parseLeaky(allocator: std.mem.Allocator, bytes: []const u8) !Authority {
    const value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{});
    return fromJsonValue(allocator, value);
}

pub fn fromJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !Authority {
    const obj = try object(value);
    const authority_version = try requiredString(obj, "authority_version");
    if (!std.mem.eql(u8, authority_version, VERSION)) {
        return error.UnsupportedChimeraAuthorityVersion;
    }
    const profile_schema_version = try requiredString(obj, "profile_schema_version");
    if (!std.mem.eql(u8, profile_schema_version, Profile.VERSION)) {
        return error.UnsupportedChimeraProfileVersion;
    }

    const profile_value = obj.get("profile") orelse return error.InvalidChimeraAuthority;
    const profile = try Profile.fromJsonValue(allocator, profile_value);
    const network = try networkFromValue(obj.get("network") orelse return error.InvalidChimeraAuthority);
    const diagnostics = diagnosticsFromValue(obj.get("diagnostics")) catch Diagnostics{};
    const profile_id = try requiredString(obj, "profile_id");
    const target_domain = try requiredString(obj, "target_domain");
    if (!std.mem.eql(u8, profile_id, profile.profile_id)) {
        return error.InvalidChimeraAuthority;
    }
    if (!std.mem.eql(u8, target_domain, profile.target_domain)) {
        return error.InvalidChimeraAuthority;
    }
    if (profile.capabilities.requires_proxy and !network.requires_proxy) {
        return error.InvalidChimeraAuthority;
    }
    if ((profile.capabilities.requires_proxy or network.requires_proxy) and network.proxy_url.len == 0) {
        return error.InvalidChimeraAuthority;
    }
    if ((profile.capabilities.requires_curl_impersonate or
        profile.transport.requires_curl_impersonate or
        diagnostics.requires_curl_impersonate) and
        profile.transport.impersonate_target == null)
    {
        return error.InvalidChimeraAuthority;
    }

    return .{
        .authority_version = authority_version,
        .profile_schema_version = profile_schema_version,
        .profile_id = profile_id,
        .target_domain = target_domain,
        .profile = profile,
        .network = network,
        .diagnostics = diagnostics,
    };
}

fn networkFromValue(value: std.json.Value) !Network {
    const obj = try object(value);
    return .{
        .proxy_url = try requiredString(obj, "proxy_url"),
        .route_id = optionalString(obj, "route_id") catch null,
        .proxy_route = optionalString(obj, "proxy_route") catch null,
        .requires_proxy = optionalBool(obj, "requires_proxy") catch true,
    };
}

fn diagnosticsFromValue(value: ?std.json.Value) !Diagnostics {
    const raw = value orelse return .{};
    const obj = try object(raw);
    return .{
        .expected_impersonation_target = optionalString(obj, "expected_impersonation_target") catch null,
        .requires_curl_impersonate = optionalBool(obj, "requires_curl_impersonate") catch false,
    };
}

fn object(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |obj| obj,
        else => error.InvalidChimeraAuthority,
    };
}

fn requiredString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = obj.get(key) orelse return error.InvalidChimeraAuthority;
    return switch (value) {
        .string => |str| if (str.len > 0) str else error.InvalidChimeraAuthority,
        else => error.InvalidChimeraAuthority,
    };
}

fn optionalString(obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .string => |str| if (str.len > 0) str else null,
        .null => null,
        else => error.InvalidChimeraAuthority,
    };
}

fn optionalBool(obj: std.json.ObjectMap, key: []const u8) !bool {
    const value = obj.get(key) orelse return false;
    return switch (value) {
        .bool => |b| b,
        .null => false,
        else => error.InvalidChimeraAuthority,
    };
}

test "Chimera Authority parses managed launch authority" {
    const testing = @import("../testing.zig");
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const authority = try Authority.parseLeaky(arena.allocator(),
        \\{
        \\  "authority_version":"chimera-lightpanda-authority/v1",
        \\  "profile_schema_version":"chimera-browser-profile/v1",
        \\  "profile_id":"lightpanda:sess-1",
        \\  "target_domain":"example.com",
        \\  "profile":{
        \\    "schema_version":"chimera-browser-profile/v1",
        \\    "profile_id":"lightpanda:sess-1",
        \\    "target_domain":"example.com",
        \\    "user_agent":"Mozilla/5.0",
        \\    "app_version":"5.0",
        \\    "accept_language":"en-AU,en;q=0.9",
        \\    "languages":["en-AU","en"],
        \\    "headers":{
        \\      "User-Agent":"Mozilla/5.0",
        \\      "Accept-Language":"en-AU,en;q=0.9",
        \\      "Sec-CH-UA":"\"Chromium\";v=\"136\"",
        \\      "Sec-CH-UA-Mobile":"?0",
        \\      "Sec-CH-UA-Platform":"\"macOS\""
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
        \\      "platform_version":"15.0.0",
        \\      "ua_full_version":"136.0.0.0",
        \\      "wow64":false,
        \\      "form_factor":["Desktop"]
        \\    },
        \\    "seeds":{
        \\      "canvas":111,
        \\      "audio":222,
        \\      "font":333,
        \\      "human":444
        \\    },
        \\    "plugins":{
        \\      "pdf_enabled":true
        \\    },
        \\    "canvas":{
        \\      "enabled":true,
        \\      "seed":111
        \\    },
        \\    "audio":{
        \\      "enabled":true,
        \\      "seed":222
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
        \\    "proxy_url":"http://routejson.token:secret@127.0.0.1:8080",
        \\    "route_id":"exit-a",
        \\    "proxy_route":"lock:exit-a:sess-1:lightpanda",
        \\    "requires_proxy":true
        \\  },
        \\  "diagnostics":{
        \\    "expected_impersonation_target":"chrome136",
        \\    "requires_curl_impersonate":true
        \\  }
        \\}
    );

    try testing.expectString("chimera-lightpanda-authority/v1", authority.authority_version);
    try testing.expectString("lightpanda:sess-1", authority.profile_id);
    try testing.expectString("http://routejson.token:secret@127.0.0.1:8080", authority.network.proxy_url);
    try testing.expectString("chrome136", authority.profile.transport.impersonate_target.?);
    try testing.expect(authority.diagnostics.requires_curl_impersonate);
}
