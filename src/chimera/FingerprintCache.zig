const std = @import("std");
const Profile = @import("Profile.zig");
const Seeds = @import("Seeds.zig");

const FingerprintCache = @This();
const Allocator = std.mem.Allocator;

canvas_pixels: [256 * 256 * 4]u8,
webgl_params: WebGLParams,
font_list: []const []const u8,

pub const WebGLParams = struct {
    vendor: []const u8,
    renderer: []const u8,
    version: []const u8,
    shading_language_version: []const u8,
    max_texture_size: i32 = 16384,
    max_cube_map_texture_size: i32 = 16384,
    max_renderbuffer_size: i32 = 16384,
    max_vertex_attribs: i32 = 16,
    max_vertex_texture_image_units: i32 = 16,
    max_texture_image_units: i32 = 16,
    max_combined_texture_image_units: i32 = 32,
    max_fragment_uniform_vectors: i32 = 1024,
    max_vertex_uniform_vectors: i32 = 4096,
    max_varying_vectors: i32 = 30,
    red_bits: i32 = 8,
    green_bits: i32 = 8,
    blue_bits: i32 = 8,
    alpha_bits: i32 = 8,
    depth_bits: i32 = 24,
    stencil_bits: i32 = 8,
    aliased_point_size_range: [2]f32 = .{ 1.0, 255.75 },
    aliased_line_width_range: [2]f32 = .{ 1.0, 1.0 },
    sample_buffers: i32 = 1,
    samples: i32 = 4,
};

pub const CacheKey = struct {
    profile_id: []const u8,
    canvas_seed: u64,
    font_seed: u64,
    webgl_vendor: []const u8,
    webgl_renderer: []const u8,

    pub fn hash(self: CacheKey) [32]u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(self.profile_id);
        hasher.update(std.mem.asBytes(&self.canvas_seed));
        hasher.update(std.mem.asBytes(&self.font_seed));
        hasher.update(self.webgl_vendor);
        hasher.update(self.webgl_renderer);
        return hasher.finalResult();
    }
};

pub const PlatformFontList = struct {
    const macos_fonts = [_][]const u8{
        "Arial",           "Arial Black",    "Courier New",
        "Georgia",         "Helvetica",      "Helvetica Neue",
        "Impact",          "Lucida Grande",  "Monaco",
        "Palatino",        "SF Pro Display", "SF Pro Text",
        "Times New Roman", "Trebuchet MS",   "Verdana",
    };

    const windows_fonts = [_][]const u8{
        "Arial",          "Arial Black",          "Calibri",
        "Cambria",        "Candara",              "Comic Sans MS",
        "Consolas",       "Constantia",           "Corbel",
        "Courier New",    "Georgia",              "Impact",
        "Lucida Console", "Microsoft Sans Serif", "Palatino Linotype",
        "Segoe UI",       "Tahoma",               "Times New Roman",
        "Trebuchet MS",   "Verdana",
    };

    const linux_fonts = [_][]const u8{
        "Arial",           "Courier New",         "DejaVu Sans",
        "DejaVu Serif",    "Droid Sans Fallback", "Georgia",
        "Liberation Mono", "Liberation Sans",     "Nimbus Sans L",
        "Nimbus Roman",    "Times New Roman",     "Verdana",
    };

    pub fn forPlatform(platform: []const u8) []const []const u8 {
        if (isMacPlatform(platform)) return &macos_fonts;
        if (isWindowsPlatform(platform)) return &windows_fonts;
        if (isLinuxPlatform(platform)) return &linux_fonts;
        return &macos_fonts;
    }

    fn isMacPlatform(platform: []const u8) bool {
        return containsIgnoreCase(platform, "mac");
    }

    fn isWindowsPlatform(platform: []const u8) bool {
        return containsIgnoreCase(platform, "win");
    }

    fn isLinuxPlatform(platform: []const u8) bool {
        return containsIgnoreCase(platform, "linux") or containsIgnoreCase(platform, "x11");
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;
        var i: usize = 0;
        while (i + needle.len <= haystack.len) : (i += 1) {
            if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
        }
        return false;
    }
};

pub fn generate(allocator: Allocator, profile: *const Profile) !FingerprintCache {
    const canvas_pixels = generateCanvasNoise(profile.canvas.seed);
    const webgl_params = generateWebGLParams(profile);
    const font_list = try generateFontList(allocator, profile);

    return .{
        .canvas_pixels = canvas_pixels,
        .webgl_params = webgl_params,
        .font_list = font_list,
    };
}

fn generateCanvasNoise(seed: u64) [256 * 256 * 4]u8 {
    var pixels: [256 * 256 * 4]u8 = undefined;
    var pos: usize = 0;
    var y: i64 = 0;
    while (y < 256) : (y += 1) {
        var x: i64 = 0;
        while (x < 256) : (x += 1) {
            const r = noisyChannel(128, seed, x, y, 0);
            const g = noisyChannel(128, seed, x, y, 1);
            const b = noisyChannel(128, seed, x, y, 2);
            pixels[pos] = r;
            pixels[pos + 1] = g;
            pixels[pos + 2] = b;
            pixels[pos + 3] = 255;
            pos += 4;
        }
    }
    return pixels;
}

fn noisyChannel(value: u8, seed: u64, x: i64, y: i64, channel: u8) u8 {
    const ux: u64 = @bitCast(x);
    const uy: u64 = @bitCast(y);
    const rotated_y = (uy << 17) | (uy >> 47);
    const mixed = Seeds.mix(seed, ux ^ rotated_y ^ (@as(u64, channel) << 56));
    const delta = @as(i16, @intCast(mixed % 3)) - 1;
    const adjusted = @as(i16, @intCast(value)) + delta;
    if (adjusted <= 0) return 0;
    if (adjusted >= 255) return 255;
    return @intCast(adjusted);
}

fn generateWebGLParams(profile: *const Profile) WebGLParams {
    var params = WebGLParams{
        .vendor = profile.webgl.vendor orelse "WebKit",
        .renderer = profile.webgl.renderer orelse "WebKit WebGL",
        .version = "WebGL 2.0 (OpenGL ES 3.0 Chromium)",
        .shading_language_version = "WebGL GLSL ES 3.0 (OpenGL ES GLSL ES 3.0 Chromium)",
    };

    if (profile.webgl.enabled) {
        const seed = profile.seeds.canvas;
        params.max_texture_size = 16384;
        params.max_vertex_attribs = 16;
        params.max_fragment_uniform_vectors = 1024;
        params.max_vertex_uniform_vectors = 4096;
        params.max_varying_vectors = 30;

        const variation = @as(u8, @truncate(Seeds.mix(seed, 0x576F6C66) % 4));
        params.red_bits = 8;
        params.green_bits = 8;
        params.blue_bits = 8;
        params.alpha_bits = 8;
        params.depth_bits = 24 + @as(i32, @intCast(variation % 2));
        params.stencil_bits = 8;

        const point_variation = Seeds.mix(seed, 0x506F696E) % 3;
        params.aliased_point_size_range = switch (point_variation) {
            0 => .{ 1.0, 255.75 },
            1 => .{ 1.0, 256.0 },
            else => .{ 0.5, 255.0 },
        };
    }

    return params;
}

fn generateFontList(allocator: Allocator, profile: *const Profile) ![]const []const u8 {
    const platform = profile.navigator.platform;
    const base_fonts = PlatformFontList.forPlatform(platform);

    const font_seed = profile.seeds.font;
    const font_count = base_fonts.len;
    var selected_count: usize = font_count;

    const variation = Seeds.mix(font_seed, 0x466F6E74) % 4;
    selected_count = @max(8, @min(font_count, font_count - variation));

    var result = try allocator.alloc([]const u8, selected_count);
    var indices = try allocator.alloc(usize, font_count);
    defer allocator.free(indices);

    for (0..font_count) |i| {
        indices[i] = i;
    }

    var shuffle_idx: usize = font_count - 1;
    while (shuffle_idx > 0) : (shuffle_idx -= 1) {
        const swap_idx = Seeds.mix(font_seed, @as(u64, shuffle_idx)) % (shuffle_idx + 1);
        const temp = indices[shuffle_idx];
        indices[shuffle_idx] = indices[swap_idx];
        indices[swap_idx] = temp;
    }

    for (0..selected_count) |idx| {
        result[idx] = base_fonts[indices[idx]];
    }

    return result;
}

pub fn cachePath(allocator: Allocator, key: CacheKey) ![]const u8 {
    const hash = key.hash();
    var hex: [64]u8 = undefined;
    for (hash, 0..) |byte, i| {
        hex[i * 2] = "0123456789abcdef"[byte >> 4];
        hex[i * 2 + 1] = "0123456789abcdef"[byte & 0x0f];
    }
    return try std.fmt.allocPrint(allocator, "/tmp/lightpanda-fingerprint-cache/{s}.json", .{&hex});
}

pub fn loadFromCache(allocator: Allocator, profile: *const Profile) ?FingerprintCache {
    const key = CacheKey{
        .profile_id = profile.profile_id,
        .canvas_seed = profile.canvas.seed,
        .font_seed = profile.seeds.font,
        .webgl_vendor = profile.webgl.vendor orelse "",
        .webgl_renderer = profile.webgl.renderer orelse "",
    };

    const path = cachePath(allocator, key) catch return null;
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    const bytes = file.readToEndAlloc(allocator, 1024 * 1024) catch return null;
    defer allocator.free(bytes);

    return parseCacheJSON(allocator, bytes) catch null;
}

fn parseCacheJSON(allocator: Allocator, bytes: []const u8) !FingerprintCache {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const canvas_obj = root.object.get("canvas") orelse return error.InvalidCache;
    const pixels_str = canvas_obj.get("pixels") orelse return error.InvalidCache;
    const pixels_b64 = switch (pixels_str) {
        .string => |s| s,
        else => return error.InvalidCache,
    };

    const decoded = try base64Decode(allocator, pixels_b64);
    defer allocator.free(decoded);

    if (decoded.len != 256 * 256 * 4) return error.InvalidCache;
    var pixels: [256 * 256 * 4]u8 = undefined;
    @memcpy(&pixels, decoded);

    const webgl_obj = root.object.get("webgl") orelse return error.InvalidCache;
    const webgl_params = WebGLParams{
        .vendor = try requiredString(webgl_obj, "vendor"),
        .renderer = try requiredString(webgl_obj, "renderer"),
        .version = try requiredString(webgl_obj, "version"),
        .shading_language_version = try requiredString(webgl_obj, "shading_language_version"),
    };

    const fonts_arr = root.object.get("fonts") orelse return error.InvalidCache;
    const font_items = switch (fonts_arr) {
        .array => |arr| arr.items,
        else => return error.InvalidCache,
    };
    var font_list = try allocator.alloc([]const u8, font_items.len);
    for (font_items, 0..) |item, i| {
        font_list[i] = switch (item) {
            .string => |s| try allocator.dupe(u8, s),
            else => return error.InvalidCache,
        };
    }

    return .{
        .canvas_pixels = pixels,
        .webgl_params = webgl_params,
        .font_list = font_list,
    };
}

pub fn storeToCache(allocator: Allocator, profile: *const Profile, cache: *const FingerprintCache) !void {
    const key = CacheKey{
        .profile_id = profile.profile_id,
        .canvas_seed = profile.canvas.seed,
        .font_seed = profile.seeds.font,
        .webgl_vendor = profile.webgl.vendor orelse "",
        .webgl_renderer = profile.webgl.renderer orelse "",
    };

    const path = cachePath(allocator, key) catch return;
    defer allocator.free(path);

    std.fs.cwd().makePath(std.fs.path.dirname(path) orelse "/tmp/lightpanda-fingerprint-cache") catch {};

    const b64 = try base64Encode(allocator, &cache.canvas_pixels);
    defer allocator.free(b64);

    var json = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer json.deinit(allocator);

    var writer = json.writer(allocator);

    try writer.writeAll("{\n");
    try writer.print("  \"canvas\": {{\n    \"pixels\": \"{s}\"\n  }},\n", .{b64});
    try writer.writeAll("  \"webgl\": {\n");
    try writer.print("    \"vendor\": \"{s}\",\n", .{cache.webgl_params.vendor});
    try writer.print("    \"renderer\": \"{s}\",\n", .{cache.webgl_params.renderer});
    try writer.print("    \"version\": \"{s}\",\n", .{cache.webgl_params.version});
    try writer.print("    \"shading_language_version\": \"{s}\"\n", .{cache.webgl_params.shading_language_version});
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"fonts\": [\n");
    for (cache.font_list, 0..) |font, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("    \"{s}\"", .{font});
    }
    try writer.writeAll("\n  ]\n");
    try writer.writeAll("}\n");

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(json.items);
}

fn base64Encode(allocator: Allocator, data: []const u8) ![]const u8 {
    const encoder = std.base64.standard;
    const encoded_len = encoder.calcSize(data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = encoder.encode(encoded, data);
    return encoded;
}

fn base64Decode(allocator: Allocator, encoded: []const u8) ![]const u8 {
    const decoder = std.base64.standard;
    const decoded_len = try decoder.calcSizeForSlice(encoded);
    const decoded = try allocator.alloc(u8, decoded_len);
    _ = try decoder.decode(decoded, encoded);
    return decoded;
}

fn requiredString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = obj.get(key) orelse return error.InvalidCache;
    return switch (value) {
        .string => |str| str,
        else => return error.InvalidCache,
    };
}

pub fn deinit(self: *FingerprintCache, allocator: Allocator) void {
    if (self.font_list.len > 0) {
        for (self.font_list) |font| {
            allocator.free(font);
        }
        allocator.free(self.font_list);
    }
}

test "Chimera FingerprintCache generates deterministic canvas noise" {
    const testing = std.testing;

    const profile_json =
        \\{
        \\  "schema_version":"chimera-browser-profile/v1",
        \\  "profile_id":"test-cache-1",
        \\  "target_domain":"example.com",
        \\  "user_agent":"Mozilla/5.0",
        \\  "app_version":"5.0",
        \\  "accept_language":"en-US,en;q=0.9",
        \\  "languages":["en-US","en"],
        \\  "headers":{
        \\    "User-Agent":"Mozilla/5.0",
        \\    "Accept-Language":"en-US,en;q=0.9",
        \\    "Sec-CH-UA":"\"Chromium\";v=\"136\"",
        \\    "Sec-CH-UA-Mobile":"?0",
        \\    "Sec-CH-UA-Platform":"\"macOS\"",
        \\    "Sec-CH-UA-Full-Version":"\"136.0.0.0\"",
        \\    "Sec-CH-UA-Full-Version-List":"\"Chromium\";v=\"136.0.0.0\"",
        \\    "Sec-CH-UA-Arch":"\"arm\"",
        \\    "Sec-CH-UA-Bitness":"\"64\"",
        \\    "Sec-CH-UA-Model":"\"\"",
        \\    "Sec-CH-UA-Platform-Version":"\"27.0.0\""
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
        \\    "platform_version":"27.0.0",
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
        \\    "enabled":false,
        \\    "exit_ip":null
        \\  },
        \\  "storage":{
        \\    "quota_bytes":5368709120,
        \\    "usage_bytes":0
        \\  },
        \\  "capabilities":{
        \\    "requires_proxy":true,
        \\    "requires_webrtc_exit_ip":false,
        \\    "requires_curl_impersonate":true
        \\  }
        \\}
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), profile_json, .{});
    const profile = try Profile.fromJsonValue(arena.allocator(), value);

    const cache1 = try generate(arena.allocator(), &profile);
    const cache2 = try generate(arena.allocator(), &profile);

    try testing.expectEqual(cache1.canvas_pixels, cache2.canvas_pixels);
    try testing.expectEqualStrings(cache1.webgl_params.vendor, cache2.webgl_params.vendor);
    try testing.expectEqualStrings(cache1.webgl_params.renderer, cache2.webgl_params.renderer);
    try testing.expectEqual(cache1.font_list.len, cache2.font_list.len);

    for (cache1.font_list, cache2.font_list) |f1, f2| {
        try testing.expectEqualStrings(f1, f2);
    }
}

test "Chimera FingerprintCache produces different output for different seeds" {
    const testing = std.testing;

    const profile_json_a =
        \\{
        \\  "schema_version":"chimera-browser-profile/v1",
        \\  "profile_id":"test-cache-a",
        \\  "target_domain":"example.com",
        \\  "user_agent":"Mozilla/5.0",
        \\  "app_version":"5.0",
        \\  "accept_language":"en-US,en;q=0.9",
        \\  "languages":["en-US","en"],
        \\  "headers":{
        \\    "User-Agent":"Mozilla/5.0",
        \\    "Accept-Language":"en-US,en;q=0.9",
        \\    "Sec-CH-UA":"\"Chromium\";v=\"136\"",
        \\    "Sec-CH-UA-Mobile":"?0",
        \\    "Sec-CH-UA-Platform":"\"macOS\"",
        \\    "Sec-CH-UA-Full-Version":"\"136.0.0.0\"",
        \\    "Sec-CH-UA-Full-Version-List":"\"Chromium\";v=\"136.0.0.0\"",
        \\    "Sec-CH-UA-Arch":"\"arm\"",
        \\    "Sec-CH-UA-Bitness":"\"64\"",
        \\    "Sec-CH-UA-Model":"\"\"",
        \\    "Sec-CH-UA-Platform-Version":"\"27.0.0\""
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
        \\    "platform_version":"27.0.0",
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
        \\    "enabled":false,
        \\    "exit_ip":null
        \\  },
        \\  "storage":{
        \\    "quota_bytes":5368709120,
        \\    "usage_bytes":0
        \\  },
        \\  "capabilities":{
        \\    "requires_proxy":true,
        \\    "requires_webrtc_exit_ip":false,
        \\    "requires_curl_impersonate":true
        \\  }
        \\}
    ;

    const profile_json_b =
        \\{
        \\  "schema_version":"chimera-browser-profile/v1",
        \\  "profile_id":"test-cache-b",
        \\  "target_domain":"example.com",
        \\  "user_agent":"Mozilla/5.0",
        \\  "app_version":"5.0",
        \\  "accept_language":"en-US,en;q=0.9",
        \\  "languages":["en-US","en"],
        \\  "headers":{
        \\    "User-Agent":"Mozilla/5.0",
        \\    "Accept-Language":"en-US,en;q=0.9",
        \\    "Sec-CH-UA":"\"Chromium\";v=\"136\"",
        \\    "Sec-CH-UA-Mobile":"?0",
        \\    "Sec-CH-UA-Platform":"\"macOS\"",
        \\    "Sec-CH-UA-Full-Version":"\"136.0.0.0\"",
        \\    "Sec-CH-UA-Full-Version-List":"\"Chromium\";v=\"136.0.0.0\"",
        \\    "Sec-CH-UA-Arch":"\"arm\"",
        \\    "Sec-CH-UA-Bitness":"\"64\"",
        \\    "Sec-CH-UA-Model":"\"\"",
        \\    "Sec-CH-UA-Platform-Version":"\"27.0.0\""
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
        \\    "platform_version":"27.0.0",
        \\    "ua_full_version":"136.0.0.0",
        \\    "wow64":false,
        \\    "form_factor":["Desktop"]
        \\  },
        \\  "seeds":{
        \\    "canvas":999,
        \\    "audio":222,
        \\    "font":888,
        \\    "human":444
        \\  },
        \\  "plugins":{
        \\    "pdf_enabled":true
        \\  },
        \\  "canvas":{
        \\    "enabled":true,
        \\    "seed":999
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
        \\    "enabled":false,
        \\    "exit_ip":null
        \\  },
        \\  "storage":{
        \\    "quota_bytes":5368709120,
        \\    "usage_bytes":0
        \\  },
        \\  "capabilities":{
        \\    "requires_proxy":true,
        \\    "requires_webrtc_exit_ip":false,
        \\    "requires_curl_impersonate":true
        \\  }
        \\}
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const value_a = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), profile_json_a, .{});
    const profile_a = try Profile.fromJsonValue(arena.allocator(), value_a);

    const value_b = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), profile_json_b, .{});
    const profile_b = try Profile.fromJsonValue(arena.allocator(), value_b);

    const cache_a = try generate(arena.allocator(), &profile_a);
    const cache_b = try generate(arena.allocator(), &profile_b);

    try testing.expect(cache_a.canvas_pixels != cache_b.canvas_pixels);
}
