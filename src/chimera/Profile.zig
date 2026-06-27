const std = @import("std");

pub const VERSION = "chimera-browser-profile/v1";

const Profile = @This();
const Allocator = std.mem.Allocator;

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
transport: Transport,
capabilities: Capabilities,

pub const Headers = struct {
    user_agent: []const u8,
    accept_language: []const u8,
    sec_ch_ua: []const u8,
    sec_ch_ua_mobile: []const u8,
    sec_ch_ua_platform: []const u8,
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
    const capabilities_value = obj.get("capabilities") orelse return error.InvalidChimeraProfile;
    const capabilities_obj = try object(capabilities_value);
    var transport = Transport{};
    if (obj.get("transport")) |transport_value| {
        const transport_obj = try object(transport_value);
        transport = .{
            .impersonate_target = optionalString(transport_obj, "impersonate_target") catch null,
            .requires_curl_impersonate = optionalBool(transport_obj, "requires_curl_impersonate") catch false,
        };
    }

    return .{
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
        .transport = transport,
        .capabilities = .{
            .requires_proxy = try requiredBool(capabilities_obj, "requires_proxy"),
            .requires_webrtc_exit_ip = try requiredBool(capabilities_obj, "requires_webrtc_exit_ip"),
            .requires_curl_impersonate = try requiredBool(capabilities_obj, "requires_curl_impersonate"),
        },
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

test "Chimera Profile parses managed browser identity" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(),
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
        \\    "Sec-CH-UA-Platform":"\"macOS\""
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
    , .{});
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
    try testing.expectEqualStrings("chrome136", profile.transport.impersonate_target.?);
    try testing.expect(profile.transport.requires_curl_impersonate);
    try testing.expect(profile.capabilities.requires_proxy);
}
