const std = @import("std");

pub const VERSION = "chimera-browser-profile/v1";

const Profile = @This();
const Allocator = std.mem.Allocator;
const ClientHints = @import("ClientHints.zig");

schema_version: []const u8,
profile_id: []const u8,
target_domain: []const u8,
user_agent: []const u8,
app_version: []const u8,
accept_language: []const u8,
languages: []const []const u8,
headers: Headers,
navigator: Navigator,
ua_data: UAData,
seeds: Seeds,
plugins: Plugins,
canvas: SeededSurface,
audio: SeededSurface,
webgl: WebGL,
webrtc: WebRTC,
geolocation: ?Geolocation = null,
storage: Storage,
transport: Transport,
capabilities: Capabilities,

pub const Headers = struct {
    user_agent: []const u8,
    accept_language: []const u8,
    sec_ch_ua: []const u8,
    sec_ch_ua_mobile: []const u8,
    sec_ch_ua_platform: []const u8,
    sec_ch_ua_full_version: []const u8,
    sec_ch_ua_full_version_list: []const u8,
    sec_ch_ua_arch: []const u8,
    sec_ch_ua_bitness: []const u8,
    sec_ch_ua_model: []const u8,
    sec_ch_ua_platform_version: []const u8,
};

pub const Navigator = struct {
    platform: []const u8,
    vendor: []const u8,
    product: []const u8,
    hardware_concurrency: u32,
    device_memory: f64,
    max_touch_points: u32,
    webdriver: bool,
};

pub const Brand = struct {
    brand: []const u8,
    version: []const u8,
};

pub const UAData = struct {
    brands: []const Brand,
    full_version_list: []const Brand,
    mobile: bool,
    platform: []const u8,
    architecture: []const u8,
    bitness: []const u8,
    model: []const u8,
    platform_version: []const u8,
    ua_full_version: []const u8,
    wow64: bool,
    form_factor: []const []const u8,
};

pub const Seeds = struct {
    canvas: u64,
    audio: u64,
    font: u64,
    human: u64,
};

pub const Plugins = struct {
    pdf_enabled: bool,
};

pub const SeededSurface = struct {
    enabled: bool,
    seed: u64,
};

pub const WebGL = struct {
    enabled: bool,
    vendor: ?[]const u8 = null,
    renderer: ?[]const u8 = null,
};

pub const WebRTC = struct {
    enabled: bool,
    exit_ip: ?[]const u8 = null,
};

pub const Geolocation = struct {
    latitude: f64,
    longitude: f64,
    accuracy: f64,
};

pub const Storage = struct {
    quota_bytes: u64,
    usage_bytes: u64,
};

pub const Transport = struct {
    impersonate_target: ?[]const u8 = null,
    requires_curl_impersonate: bool = false,
};

pub const Capabilities = struct {
    requires_proxy: bool,
    requires_webrtc_exit_ip: bool,
    requires_curl_impersonate: bool,
};

pub fn fromJsonValue(allocator: Allocator, value: std.json.Value) !Profile {
    const obj = try object(value);
    const schema_version = try requiredString(obj, "schema_version");
    if (!std.mem.eql(u8, schema_version, VERSION)) {
        return error.UnsupportedChimeraProfileVersion;
    }

    const headers_value = obj.get("headers") orelse return error.InvalidChimeraProfile;
    const headers_obj = try object(headers_value);
    const navigator_value = obj.get("navigator") orelse return error.InvalidChimeraProfile;
    const navigator_obj = try object(navigator_value);
    const ua_data_value = obj.get("ua_data") orelse return error.InvalidChimeraProfile;
    const ua_data_obj = try object(ua_data_value);
    const seeds_value = obj.get("seeds") orelse return error.InvalidChimeraProfile;
    const seeds_obj = try object(seeds_value);
    const plugins_value = obj.get("plugins") orelse return error.InvalidChimeraProfile;
    const plugins_obj = try object(plugins_value);
    const canvas_value = obj.get("canvas") orelse return error.InvalidChimeraProfile;
    const canvas_obj = try object(canvas_value);
    const audio_value = obj.get("audio") orelse return error.InvalidChimeraProfile;
    const audio_obj = try object(audio_value);
    const webgl_value = obj.get("webgl") orelse return error.InvalidChimeraProfile;
    const webgl_obj = try object(webgl_value);
    const webrtc_value = obj.get("webrtc") orelse return error.InvalidChimeraProfile;
    const webrtc_obj = try object(webrtc_value);
    const storage_value = obj.get("storage") orelse return error.InvalidChimeraProfile;
    const storage_obj = try object(storage_value);
    const capabilities_value = obj.get("capabilities") orelse return error.InvalidChimeraProfile;
    const capabilities_obj = try object(capabilities_value);
    var transport = Transport{};
    if (obj.get("transport")) |transport_value| {
        const transport_obj = try object(transport_value);
        transport = .{
            .impersonate_target = try optionalString(transport_obj, "impersonate_target"),
            .requires_curl_impersonate = try optionalBool(transport_obj, "requires_curl_impersonate"),
        };
    }

    const geolocation = if (obj.get("geolocation")) |geolocation_value| switch (geolocation_value) {
        .null => null,
        else => try geolocationFromValue(geolocation_value),
    } else null;
    const storage = try storageFromObject(storage_obj);
    const webgl_enabled = try requiredBool(webgl_obj, "enabled");
    const webgl_vendor = try optionalString(webgl_obj, "vendor");
    const webgl_renderer = try optionalString(webgl_obj, "renderer");
    if (webgl_enabled and (webgl_vendor == null or webgl_renderer == null)) {
        return error.InvalidChimeraProfile;
    }

    const profile = Profile{
        .schema_version = schema_version,
        .profile_id = try requiredString(obj, "profile_id"),
        .target_domain = try requiredString(obj, "target_domain"),
        .user_agent = try requiredString(obj, "user_agent"),
        .app_version = try requiredString(obj, "app_version"),
        .accept_language = try requiredString(obj, "accept_language"),
        .languages = try requiredStringList(allocator, obj, "languages"),
        .headers = .{
            .user_agent = try requiredString(headers_obj, "User-Agent"),
            .accept_language = try requiredString(headers_obj, "Accept-Language"),
            .sec_ch_ua = try requiredString(headers_obj, "Sec-CH-UA"),
            .sec_ch_ua_mobile = try requiredString(headers_obj, "Sec-CH-UA-Mobile"),
            .sec_ch_ua_platform = try requiredString(headers_obj, "Sec-CH-UA-Platform"),
            .sec_ch_ua_full_version = try requiredString(headers_obj, "Sec-CH-UA-Full-Version"),
            .sec_ch_ua_full_version_list = try requiredString(headers_obj, "Sec-CH-UA-Full-Version-List"),
            .sec_ch_ua_arch = try requiredString(headers_obj, "Sec-CH-UA-Arch"),
            .sec_ch_ua_bitness = try requiredString(headers_obj, "Sec-CH-UA-Bitness"),
            .sec_ch_ua_model = try requiredString(headers_obj, "Sec-CH-UA-Model"),
            .sec_ch_ua_platform_version = try requiredString(headers_obj, "Sec-CH-UA-Platform-Version"),
        },
        .navigator = .{
            .platform = try requiredString(navigator_obj, "platform"),
            .vendor = try requiredString(navigator_obj, "vendor"),
            .product = try requiredString(navigator_obj, "product"),
            .hardware_concurrency = try requiredU32(navigator_obj, "hardware_concurrency"),
            .device_memory = try requiredF64(navigator_obj, "device_memory"),
            .max_touch_points = try requiredU32(navigator_obj, "max_touch_points"),
            .webdriver = try requiredBool(navigator_obj, "webdriver"),
        },
        .ua_data = .{
            .brands = try requiredBrandList(allocator, ua_data_obj, "brands"),
            .full_version_list = try requiredBrandList(allocator, ua_data_obj, "full_version_list"),
            .mobile = try requiredBool(ua_data_obj, "mobile"),
            .platform = try requiredString(ua_data_obj, "platform"),
            .architecture = try requiredString(ua_data_obj, "architecture"),
            .bitness = try requiredString(ua_data_obj, "bitness"),
            .model = (try optionalString(ua_data_obj, "model")) orelse "",
            .platform_version = try requiredString(ua_data_obj, "platform_version"),
            .ua_full_version = try requiredString(ua_data_obj, "ua_full_version"),
            .wow64 = try requiredBool(ua_data_obj, "wow64"),
            .form_factor = try requiredStringList(allocator, ua_data_obj, "form_factor"),
        },
        .seeds = .{
            .canvas = try requiredU64(seeds_obj, "canvas"),
            .audio = try requiredU64(seeds_obj, "audio"),
            .font = try requiredU64(seeds_obj, "font"),
            .human = try requiredU64(seeds_obj, "human"),
        },
        .plugins = .{
            .pdf_enabled = try requiredBool(plugins_obj, "pdf_enabled"),
        },
        .canvas = .{
            .enabled = try requiredBool(canvas_obj, "enabled"),
            .seed = try requiredU64(canvas_obj, "seed"),
        },
        .audio = .{
            .enabled = try requiredBool(audio_obj, "enabled"),
            .seed = try requiredU64(audio_obj, "seed"),
        },
        .webgl = .{
            .enabled = webgl_enabled,
            .vendor = webgl_vendor,
            .renderer = webgl_renderer,
        },
        .webrtc = .{
            .enabled = try requiredBool(webrtc_obj, "enabled"),
            .exit_ip = try optionalString(webrtc_obj, "exit_ip"),
        },
        .geolocation = geolocation,
        .storage = storage,
        .transport = transport,
        .capabilities = .{
            .requires_proxy = try requiredBool(capabilities_obj, "requires_proxy"),
            .requires_webrtc_exit_ip = try requiredBool(capabilities_obj, "requires_webrtc_exit_ip"),
            .requires_curl_impersonate = try requiredBool(capabilities_obj, "requires_curl_impersonate"),
        },
    };
    try validateCapabilityRequirements(&profile);
    try validateIdentityCoherence(allocator, &profile);
    return profile;
}

fn validateCapabilityRequirements(profile: *const Profile) !void {
    if (profile.capabilities.requires_webrtc_exit_ip and (!profile.webrtc.enabled or profile.webrtc.exit_ip == null)) {
        return error.InvalidChimeraProfile;
    }
}

fn validateIdentityCoherence(allocator: Allocator, profile: *const Profile) !void {
    if (!std.mem.eql(u8, profile.user_agent, profile.headers.user_agent)) {
        return error.InvalidChimeraProfile;
    }
    if (!std.mem.eql(u8, profile.accept_language, profile.headers.accept_language)) {
        return error.InvalidChimeraProfile;
    }
    try validateAcceptLanguageList(profile.accept_language, profile.languages);
    try expectBrandListValue(allocator, profile.headers.sec_ch_ua, profile.ua_data.brands);
    try expectBrandListValue(allocator, profile.headers.sec_ch_ua_full_version_list, profile.ua_data.full_version_list);
    try expectQuotedValue(allocator, profile.headers.sec_ch_ua_platform, profile.ua_data.platform);
    try expectQuotedValue(allocator, profile.headers.sec_ch_ua_full_version, profile.ua_data.ua_full_version);
    try expectQuotedValue(allocator, profile.headers.sec_ch_ua_arch, profile.ua_data.architecture);
    try expectQuotedValue(allocator, profile.headers.sec_ch_ua_bitness, profile.ua_data.bitness);
    try expectQuotedValue(allocator, profile.headers.sec_ch_ua_model, profile.ua_data.model);
    try expectQuotedValue(allocator, profile.headers.sec_ch_ua_platform_version, profile.ua_data.platform_version);
    if (!std.mem.eql(u8, profile.headers.sec_ch_ua_mobile, ClientHints.mobileValue(profile.ua_data.mobile))) {
        return error.InvalidChimeraProfile;
    }
}

fn validateAcceptLanguageList(accept_language: []const u8, languages: []const []const u8) !void {
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, accept_language, ',');
    while (it.next()) |part| {
        const end = std.mem.indexOfScalar(u8, part, ';') orelse part.len;
        const language = std.mem.trim(u8, part[0..end], " \t");
        if (language.len == 0) continue;
        if (count >= languages.len or !std.mem.eql(u8, language, languages[count])) {
            return error.InvalidChimeraProfile;
        }
        count += 1;
    }
    if (count != languages.len) return error.InvalidChimeraProfile;
}

fn expectBrandListValue(allocator: Allocator, actual: []const u8, brands: []const Brand) !void {
    const expected = ClientHints.formatBrandListValue(allocator, brands) catch |err| switch (err) {
        error.InvalidClientHintValue => return error.InvalidChimeraProfile,
        else => return err,
    };
    defer allocator.free(expected);
    if (!std.mem.eql(u8, actual, expected)) {
        return error.InvalidChimeraProfile;
    }
}

fn expectQuotedValue(allocator: Allocator, actual: []const u8, value: []const u8) !void {
    const expected = ClientHints.formatQuotedValue(allocator, value) catch |err| switch (err) {
        error.InvalidClientHintValue => return error.InvalidChimeraProfile,
        else => return err,
    };
    defer allocator.free(expected);
    if (!std.mem.eql(u8, actual, expected)) {
        return error.InvalidChimeraProfile;
    }
}

fn geolocationFromValue(value: std.json.Value) !Geolocation {
    const obj = try object(value);
    const latitude = try requiredF64(obj, "latitude");
    const longitude = try requiredF64(obj, "longitude");
    const accuracy = try requiredF64(obj, "accuracy");
    if (latitude < -90 or latitude > 90) return error.InvalidChimeraProfile;
    if (longitude < -180 or longitude > 180) return error.InvalidChimeraProfile;
    if (accuracy <= 0) return error.InvalidChimeraProfile;
    return .{
        .latitude = latitude,
        .longitude = longitude,
        .accuracy = accuracy,
    };
}

fn storageFromObject(obj: std.json.ObjectMap) !Storage {
    const quota_bytes = try requiredU64(obj, "quota_bytes");
    const usage_bytes = try requiredU64(obj, "usage_bytes");
    if (quota_bytes == 0 or usage_bytes > quota_bytes) return error.InvalidChimeraProfile;
    return .{
        .quota_bytes = quota_bytes,
        .usage_bytes = usage_bytes,
    };
}

fn object(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |obj| obj,
        else => error.InvalidChimeraProfile,
    };
}

fn requiredString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = obj.get(key) orelse return error.InvalidChimeraProfile;
    return switch (value) {
        .string => |str| if (str.len > 0) str else error.InvalidChimeraProfile,
        else => error.InvalidChimeraProfile,
    };
}

fn optionalString(obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .string => |str| if (str.len > 0) str else null,
        .null => null,
        else => error.InvalidChimeraProfile,
    };
}

fn requiredStringList(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) ![]const []const u8 {
    const value = obj.get(key) orelse return error.InvalidChimeraProfile;
    const items = switch (value) {
        .array => |arr| arr.items,
        else => return error.InvalidChimeraProfile,
    };
    if (items.len == 0) return error.InvalidChimeraProfile;

    const out = try allocator.alloc([]const u8, items.len);
    for (items, 0..) |item, i| {
        out[i] = switch (item) {
            .string => |str| if (str.len > 0) str else return error.InvalidChimeraProfile,
            else => return error.InvalidChimeraProfile,
        };
    }
    return out;
}

fn requiredBrandList(allocator: Allocator, obj: std.json.ObjectMap, key: []const u8) ![]const Brand {
    const value = obj.get(key) orelse return error.InvalidChimeraProfile;
    const items = switch (value) {
        .array => |arr| arr.items,
        else => return error.InvalidChimeraProfile,
    };
    if (items.len == 0) return error.InvalidChimeraProfile;

    const out = try allocator.alloc(Brand, items.len);
    for (items, 0..) |item, i| {
        const brand_obj = try object(item);
        out[i] = .{
            .brand = try requiredString(brand_obj, "brand"),
            .version = try requiredString(brand_obj, "version"),
        };
    }
    return out;
}

fn optionalBool(obj: std.json.ObjectMap, key: []const u8) !bool {
    const value = obj.get(key) orelse return false;
    return switch (value) {
        .bool => |b| b,
        .null => false,
        else => error.InvalidChimeraProfile,
    };
}

fn requiredBool(obj: std.json.ObjectMap, key: []const u8) !bool {
    const value = obj.get(key) orelse return error.InvalidChimeraProfile;
    return switch (value) {
        .bool => |b| b,
        else => error.InvalidChimeraProfile,
    };
}

fn requiredU32(obj: std.json.ObjectMap, key: []const u8) !u32 {
    const value = obj.get(key) orelse return error.InvalidChimeraProfile;
    const raw = switch (value) {
        .integer => |n| n,
        else => return error.InvalidChimeraProfile,
    };
    if (raw < 0 or raw > std.math.maxInt(u32)) return error.InvalidChimeraProfile;
    return @intCast(raw);
}

fn requiredU64(obj: std.json.ObjectMap, key: []const u8) !u64 {
    const value = obj.get(key) orelse return error.InvalidChimeraProfile;
    const raw = switch (value) {
        .integer => |n| n,
        else => return error.InvalidChimeraProfile,
    };
    if (raw < 0) return error.InvalidChimeraProfile;
    return @intCast(raw);
}

fn requiredF64(obj: std.json.ObjectMap, key: []const u8) !f64 {
    const value = obj.get(key) orelse return error.InvalidChimeraProfile;
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => error.InvalidChimeraProfile,
    };
}

const test_profile_json =
    \\{
    \\  "schema_version":"chimera-browser-profile/v1",
    \\  "profile_id":"lightpanda:sess-1",
    \\  "target_domain":"example.com",
    \\  "user_agent":"Mozilla/5.0",
    \\  "app_version":"5.0",
    \\  "accept_language":"en-AU,en;q=0.9",
    \\  "languages":["en-AU","en"],
    \\  "headers":{
    \\    "User-Agent":"Mozilla/5.0",
    \\    "Accept-Language":"en-AU,en;q=0.9",
    \\    "Sec-CH-UA":"\"Chromium\";v=\"136\"",
    \\    "Sec-CH-UA-Mobile":"?0",
    \\    "Sec-CH-UA-Platform":"\"macOS\"",
    \\    "Sec-CH-UA-Full-Version":"\"136.0.0.0\"",
    \\    "Sec-CH-UA-Full-Version-List":"\"Chromium\";v=\"136.0.0.0\"",
    \\    "Sec-CH-UA-Arch":"\"arm\"",
    \\    "Sec-CH-UA-Bitness":"\"64\"",
    \\    "Sec-CH-UA-Model":"\"\"",
    \\    "Sec-CH-UA-Platform-Version":"\"15.0.0\""
    \\  },
    \\  "navigator":{
    \\    "platform":"MacIntel",
    \\    "vendor":"Google Inc.",
    \\    "product":"Gecko",
    \\    "hardware_concurrency":8,
    \\    "device_memory":8,
    \\    "max_touch_points":0,
    \\    "webdriver":false
    \\  },
    \\  "ua_data":{
    \\    "brands":[{"brand":"Chromium","version":"136"}],
    \\    "full_version_list":[{"brand":"Chromium","version":"136.0.0.0"}],
    \\    "mobile":false,
    \\    "platform":"macOS",
    \\    "architecture":"arm",
    \\    "bitness":"64",
    \\    "model":"",
    \\    "platform_version":"15.0.0",
    \\    "ua_full_version":"136.0.0.0",
    \\    "wow64":false,
    \\    "form_factor":["Desktop"]
    \\  },
    \\  "seeds":{
    \\    "canvas":111,
    \\    "audio":222,
    \\    "font":333,
    \\    "human":444
    \\  },
    \\  "plugins":{
    \\    "pdf_enabled":true
    \\  },
    \\  "canvas":{
    \\    "enabled":true,
    \\    "seed":111
    \\  },
    \\  "audio":{
    \\    "enabled":true,
    \\    "seed":222
    \\  },
    \\  "webgl":{
    \\    "enabled":true,
    \\    "vendor":"Google Inc. (Apple)",
    \\    "renderer":"ANGLE (Apple, ANGLE Metal Renderer: Apple M-series, Unspecified Version)"
    \\  },
    \\  "webrtc":{
    \\    "enabled":true,
    \\    "exit_ip":"203.0.113.10"
    \\  },
    \\  "geolocation":{
    \\    "latitude":-37.81401,
    \\    "longitude":144.96317,
    \\    "accuracy":25000
    \\  },
    \\  "storage":{
    \\    "quota_bytes":5368709120,
    \\    "usage_bytes":0
    \\  },
    \\  "transport":{
    \\    "impersonate_target":"chrome136",
    \\    "requires_curl_impersonate":true
    \\  },
    \\  "capabilities":{
    \\    "requires_proxy":true,
    \\    "requires_webrtc_exit_ip":false,
    \\    "requires_curl_impersonate":true
    \\  }
    \\}
;

test "Chimera Profile parses managed browser identity" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), test_profile_json, .{});
    const profile = try Profile.fromJsonValue(arena.allocator(), value);

    try testing.expectEqualStrings("chimera-browser-profile/v1", profile.schema_version);
    try testing.expectEqualStrings("lightpanda:sess-1", profile.profile_id);
    try testing.expectEqualStrings("Mozilla/5.0", profile.headers.user_agent);
    try testing.expectEqualStrings("5.0", profile.app_version);
    try testing.expectEqualStrings("en-AU", profile.languages[0]);
    try testing.expectEqualStrings("MacIntel", profile.navigator.platform);
    try testing.expectEqualStrings("Chromium", profile.ua_data.brands[0].brand);
    try testing.expectEqual(@as(u64, 111), profile.canvas.seed);
    try testing.expect(profile.plugins.pdf_enabled);
    try testing.expect(profile.webgl.enabled);
    try testing.expectEqualStrings("Google Inc. (Apple)", profile.webgl.vendor.?);
    try testing.expectEqualStrings("ANGLE (Apple, ANGLE Metal Renderer: Apple M-series, Unspecified Version)", profile.webgl.renderer.?);
    try testing.expect(profile.webrtc.enabled);
    try testing.expectEqualStrings("203.0.113.10", profile.webrtc.exit_ip.?);
    try testing.expect(profile.geolocation != null);
    try testing.expectEqual(@as(f64, -37.81401), profile.geolocation.?.latitude);
    try testing.expectEqual(@as(f64, 144.96317), profile.geolocation.?.longitude);
    try testing.expectEqual(@as(f64, 25000), profile.geolocation.?.accuracy);
    try testing.expectEqual(@as(u64, 5 * 1024 * 1024 * 1024), profile.storage.quota_bytes);
    try testing.expectEqual(@as(u64, 0), profile.storage.usage_bytes);
    try testing.expectEqualStrings("chrome136", profile.transport.impersonate_target.?);
    try testing.expect(profile.transport.requires_curl_impersonate);
    try testing.expect(profile.capabilities.requires_proxy);
}

test "Chimera Profile rejects user agent header drift" {
    try expectMutatedProfileError(
        error.InvalidChimeraProfile,
        "\"User-Agent\":\"Mozilla/5.0\"",
        "\"User-Agent\":\"CustomBot/1.0\"",
    );
}

test "Chimera Profile rejects language identity drift" {
    try expectMutatedProfileError(
        error.InvalidChimeraProfile,
        "\"languages\":[\"en-AU\",\"en\"]",
        "\"languages\":[\"en-US\",\"en\"]",
    );
}

test "Chimera Profile rejects UA-CH full version drift" {
    try expectMutatedProfileError(
        error.InvalidChimeraProfile,
        "\"ua_full_version\":\"136.0.0.0\"",
        "\"ua_full_version\":\"137.0.0.0\"",
    );
}

test "Chimera Profile rejects UA-CH low entropy drift" {
    try expectMutatedProfileError(
        error.InvalidChimeraProfile,
        "\"platform\":\"macOS\"",
        "\"platform\":\"Windows\"",
    );
}

test "Chimera Profile rejects UA-CH high entropy drift" {
    try expectMutatedProfileError(
        error.InvalidChimeraProfile,
        "\"architecture\":\"arm\"",
        "\"architecture\":\"x86\"",
    );
}

test "Chimera Profile rejects unsafe UA-CH structured values" {
    try expectMutatedProfileError(
        error.InvalidChimeraProfile,
        "\"architecture\":\"arm\"",
        "\"architecture\":\"ar\\nm\"",
    );
}

test "Chimera Profile rejects required WebRTC exit IP when WebRTC is disabled" {
    try expectDoubleMutatedProfileError(
        error.InvalidChimeraProfile,
        "\"enabled\":true,\n    \"exit_ip\":\"203.0.113.10\"",
        "\"enabled\":false,\n    \"exit_ip\":\"203.0.113.10\"",
        "\"requires_webrtc_exit_ip\":false",
        "\"requires_webrtc_exit_ip\":true",
    );
}

fn expectMutatedProfileError(expected: anyerror, needle: []const u8, replacement: []const u8) !void {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const mutated = try std.mem.replaceOwned(u8, arena.allocator(), test_profile_json, needle, replacement);
    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), mutated, .{});
    try testing.expectError(expected, Profile.fromJsonValue(arena.allocator(), value));
}

fn expectDoubleMutatedProfileError(
    expected: anyerror,
    first_needle: []const u8,
    first_replacement: []const u8,
    second_needle: []const u8,
    second_replacement: []const u8,
) !void {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const first = try std.mem.replaceOwned(u8, arena.allocator(), test_profile_json, first_needle, first_replacement);
    const mutated = try std.mem.replaceOwned(u8, arena.allocator(), first, second_needle, second_replacement);
    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), mutated, .{});
    try testing.expectError(expected, Profile.fromJsonValue(arena.allocator(), value));
}
