const std = @import("std");

pub const Snapshot = struct {
    authority_version: ?[]const u8 = null,
    profile_schema_version: ?[]const u8 = null,
    profile_id: ?[]const u8 = null,
    route_id: ?[]const u8 = null,
    proxy_configured: bool,
    impersonation_target: ?[]const u8 = null,
    requires_curl_impersonate: bool,
    curl_impersonate_available: bool,
    impersonation_active: bool,
    header_profile_active: bool,
    navigator_profile_active: bool,
    uadata_profile_active: bool,
    plugin_profile_active: bool,
    plugin_mime_profile_active: bool,
    chrome_profile_active: bool,
    chrome_runtime_profile_active: bool,
    storage_profile_active: bool,
    storage_estimate_profile_active: bool,
    storage_persistence_profile_active: bool,
    cache_storage_profile_active: bool,
    cache_storage_semantics_active: bool,
    file_system_profile_active: bool,
    file_system_semantics_active: bool,
    canvas_profile_active: bool,
    canvas_2d_profile_active: bool,
    canvas_blob_profile_active: bool,
    offscreen_canvas_profile_active: bool,
    audio_profile_active: bool,
    audio_buffer_profile_active: bool,
    audio_graph_profile_active: bool,
    webgl_profile_active: bool,
    webgl_identity_profile_active: bool,
    webgl_caps_profile_active: bool,
    geolocation_profile_active: bool,
    geolocation_position_profile_active: bool,
    init_scripts_registered: bool = false,
    timezone_path: []const u8 = "runtime_probe",
    webrtc_supported: bool = false,
    webrtc_candidate_profile_active: bool = false,
    webrtc_exit_ip_active: bool = false,
    webrtc_exit_ip: ?[]const u8 = null,
    degraded_capabilities: []const []const u8 = &.{},
};

pub fn fromConfig(config: anytype) Snapshot {
    return fromConfigWithCurlAvailability(config, curlImpersonateAvailable(config));
}

fn fromConfigWithCurlAvailability(config: anytype, curl_impersonate_available: bool) Snapshot {
    const authority = config.chimeraAuthority();
    const target = config.curlImpersonateTarget();
    const proxy_configured = config.httpProxy() != null;

    if (authority) |loaded| {
        const profile = &loaded.profile;
        const diagnostics = loaded.diagnostics;
        const requires_curl_impersonate =
            profile.capabilities.requires_curl_impersonate or
            profile.transport.requires_curl_impersonate or
            diagnostics.requires_curl_impersonate;
        const impersonation_active = target != null and curl_impersonate_available;
        const storage_estimate_profile_active = profile.storage.quota_bytes > 0 and profile.storage.usage_bytes <= profile.storage.quota_bytes;
        const storage_persistence_profile_active = false;
        const cache_storage_semantics_active = false;
        const file_system_semantics_active = false;
        const storage_profile_active = storage_estimate_profile_active and
            storage_persistence_profile_active and
            cache_storage_semantics_active and
            file_system_semantics_active;
        const canvas_2d_profile_active = profile.canvas.enabled;
        const canvas_blob_profile_active = profile.canvas.enabled;
        const offscreen_canvas_profile_active = profile.canvas.enabled;
        const canvas_profile_active = canvas_2d_profile_active and canvas_blob_profile_active and offscreen_canvas_profile_active;
        const audio_buffer_profile_active = profile.audio.enabled;
        const audio_graph_profile_active = false;
        const audio_profile_active = audio_buffer_profile_active and audio_graph_profile_active;
        const webgl_identity_profile_active = profile.webgl.enabled and profile.webgl.vendor != null and profile.webgl.renderer != null;
        const webgl_caps_profile_active = profile.webgl.enabled;
        const webgl_profile_active = webgl_identity_profile_active and webgl_caps_profile_active;
        const geolocation_position_profile_active = profile.geolocation != null;
        const webrtc_supported = profile.webrtc.enabled;
        const webrtc_candidate_profile_active = profile.webrtc.enabled and profile.webrtc.exit_ip != null;
        const webrtc_exit_ip_active = webrtc_candidate_profile_active;

        return .{
            .authority_version = loaded.authority_version,
            .profile_schema_version = loaded.profile_schema_version,
            .profile_id = loaded.profile_id,
            .route_id = loaded.network.route_id,
            .proxy_configured = proxy_configured,
            .impersonation_target = target,
            .requires_curl_impersonate = requires_curl_impersonate,
            .curl_impersonate_available = curl_impersonate_available,
            .impersonation_active = impersonation_active,
            .header_profile_active = std.mem.eql(u8, config.http_headers.user_agent, profile.headers.user_agent),
            .navigator_profile_active = true,
            .uadata_profile_active = true,
            .plugin_profile_active = true,
            .plugin_mime_profile_active = true,
            .chrome_profile_active = true,
            .chrome_runtime_profile_active = true,
            .storage_profile_active = storage_profile_active,
            .storage_estimate_profile_active = storage_estimate_profile_active,
            .storage_persistence_profile_active = storage_persistence_profile_active,
            .cache_storage_profile_active = cache_storage_semantics_active,
            .cache_storage_semantics_active = cache_storage_semantics_active,
            .file_system_profile_active = file_system_semantics_active,
            .file_system_semantics_active = file_system_semantics_active,
            .canvas_profile_active = canvas_profile_active,
            .canvas_2d_profile_active = canvas_2d_profile_active,
            .canvas_blob_profile_active = canvas_blob_profile_active,
            .offscreen_canvas_profile_active = offscreen_canvas_profile_active,
            .audio_profile_active = audio_profile_active,
            .audio_buffer_profile_active = audio_buffer_profile_active,
            .audio_graph_profile_active = audio_graph_profile_active,
            .webgl_profile_active = webgl_profile_active,
            .webgl_identity_profile_active = webgl_identity_profile_active,
            .webgl_caps_profile_active = webgl_caps_profile_active,
            .geolocation_profile_active = geolocation_position_profile_active,
            .geolocation_position_profile_active = geolocation_position_profile_active,
            .webrtc_supported = webrtc_supported,
            .webrtc_candidate_profile_active = webrtc_candidate_profile_active,
            .webrtc_exit_ip_active = webrtc_exit_ip_active,
            .webrtc_exit_ip = profile.webrtc.exit_ip,
            .degraded_capabilities = degradedCapabilities(
                requires_curl_impersonate,
                impersonation_active,
                profile.canvas.enabled,
                canvas_profile_active,
                profile.capabilities.requires_webrtc_exit_ip,
                webrtc_exit_ip_active,
            ),
        };
    }

    return .{
        .proxy_configured = proxy_configured,
        .impersonation_target = target,
        .requires_curl_impersonate = false,
        .curl_impersonate_available = curl_impersonate_available,
        .impersonation_active = false,
        .header_profile_active = false,
        .navigator_profile_active = false,
        .uadata_profile_active = false,
        .plugin_profile_active = false,
        .plugin_mime_profile_active = false,
        .chrome_profile_active = false,
        .chrome_runtime_profile_active = false,
        .storage_profile_active = false,
        .storage_estimate_profile_active = false,
        .storage_persistence_profile_active = false,
        .cache_storage_profile_active = false,
        .cache_storage_semantics_active = false,
        .file_system_profile_active = false,
        .file_system_semantics_active = false,
        .canvas_profile_active = false,
        .canvas_2d_profile_active = false,
        .canvas_blob_profile_active = false,
        .offscreen_canvas_profile_active = false,
        .audio_profile_active = false,
        .audio_buffer_profile_active = false,
        .audio_graph_profile_active = false,
        .webgl_profile_active = false,
        .webgl_identity_profile_active = false,
        .webgl_caps_profile_active = false,
        .geolocation_profile_active = false,
        .geolocation_position_profile_active = false,
    };
}

fn curlImpersonateAvailable(config: anytype) bool {
    const ConfigType = @typeInfo(@TypeOf(config)).pointer.child;
    if (comptime @hasDecl(ConfigType, "curlImpersonateAvailable")) {
        return config.curlImpersonateAvailable();
    }
    return false;
}

fn degradedCapabilities(
    requires_curl_impersonate: bool,
    impersonation_active: bool,
    requires_canvas: bool,
    canvas_active: bool,
    requires_webrtc_exit_ip: bool,
    webrtc_exit_ip_active: bool,
) []const []const u8 {
    const curl_degraded = requires_curl_impersonate and !impersonation_active;
    const canvas_degraded = requires_canvas and !canvas_active;
    const webrtc_degraded = requires_webrtc_exit_ip and !webrtc_exit_ip_active;
    if (curl_degraded and canvas_degraded and webrtc_degraded) {
        return &.{ "curl_impersonate", "canvas", "webrtc_exit_ip" };
    }
    if (curl_degraded and canvas_degraded) {
        return &.{ "curl_impersonate", "canvas" };
    }
    if (curl_degraded and webrtc_degraded) {
        return &.{ "curl_impersonate", "webrtc_exit_ip" };
    }
    if (canvas_degraded and webrtc_degraded) {
        return &.{ "canvas", "webrtc_exit_ip" };
    }
    if (curl_degraded) {
        return &.{"curl_impersonate"};
    }
    if (canvas_degraded) {
        return &.{"canvas"};
    }
    if (webrtc_degraded) {
        return &.{"webrtc_exit_ip"};
    }
    return &.{};
}

pub fn expectProfileEvidenceTiersForTest() !void {
    const testing = std.testing;
    const Authority = @import("Authority.zig");
    const Profile = @import("Profile.zig");

    const languages = [_][]const u8{ "en-AU", "en" };
    const brands = [_]Profile.Brand{.{ .brand = "Chromium", .version = "136" }};
    const full_version_list = [_]Profile.Brand{.{ .brand = "Chromium", .version = "136.0.0.0" }};
    const form_factor = [_][]const u8{"Desktop"};
    var authority = Authority{
        .authority_version = Authority.VERSION,
        .profile_schema_version = Profile.VERSION,
        .profile_id = "lightpanda:sess-1",
        .target_domain = "example.com",
        .profile = .{
            .schema_version = Profile.VERSION,
            .profile_id = "lightpanda:sess-1",
            .target_domain = "example.com",
            .user_agent = "Mozilla/5.0",
            .app_version = "5.0",
            .accept_language = "en-AU,en;q=0.9",
            .languages = languages[0..],
            .headers = .{
                .user_agent = "Mozilla/5.0",
                .accept_language = "en-AU,en;q=0.9",
                .sec_ch_ua = "\"Chromium\";v=\"136\"",
                .sec_ch_ua_mobile = "?0",
                .sec_ch_ua_platform = "\"macOS\"",
                .sec_ch_ua_full_version = "\"136.0.0.0\"",
                .sec_ch_ua_full_version_list = "\"Chromium\";v=\"136.0.0.0\"",
                .sec_ch_ua_arch = "\"arm\"",
                .sec_ch_ua_bitness = "\"64\"",
                .sec_ch_ua_model = "\"\"",
                .sec_ch_ua_platform_version = "\"15.0.0\"",
            },
            .navigator = .{
                .platform = "MacIntel",
                .vendor = "Google Inc.",
                .product = "Gecko",
                .hardware_concurrency = 8,
                .device_memory = 8,
                .max_touch_points = 0,
                .webdriver = false,
            },
            .ua_data = .{
                .brands = brands[0..],
                .full_version_list = full_version_list[0..],
                .mobile = false,
                .platform = "macOS",
                .architecture = "arm",
                .bitness = "64",
                .model = "",
                .platform_version = "15.0.0",
                .ua_full_version = "136.0.0.0",
                .wow64 = false,
                .form_factor = form_factor[0..],
            },
            .seeds = .{ .canvas = 111, .audio = 222, .font = 333, .human = 444 },
            .plugins = .{ .pdf_enabled = true },
            .canvas = .{ .enabled = true, .seed = 111 },
            .audio = .{ .enabled = true, .seed = 222 },
            .webgl = .{
                .enabled = true,
                .vendor = "Google Inc. (Apple)",
                .renderer = "ANGLE (Apple, ANGLE Metal Renderer: Apple M-series, Unspecified Version)",
            },
            .webrtc = .{ .enabled = false, .exit_ip = null },
            .storage = .{ .quota_bytes = 5 * 1024 * 1024 * 1024, .usage_bytes = 0 },
            .transport = .{ .impersonate_target = null, .requires_curl_impersonate = false },
            .capabilities = .{
                .requires_proxy = true,
                .requires_webrtc_exit_ip = false,
                .requires_curl_impersonate = false,
            },
        },
        .network = .{
            .proxy_url = "http://routejson.token:secret@127.0.0.1:8080",
            .route_id = "exit-a",
            .proxy_route = "lock:exit-a:sess-1:lightpanda",
            .requires_proxy = true,
        },
        .diagnostics = .{},
    };

    const Config = struct {
        authority: *const Authority,
        http_headers: struct { user_agent: []const u8 },

        fn chimeraAuthority(self: *const @This()) ?*const Authority {
            return self.authority;
        }

        fn curlImpersonateTarget(_: *const @This()) ?[]const u8 {
            return null;
        }

        fn httpProxy(_: *const @This()) ?[]const u8 {
            return "http://routejson.token:secret@127.0.0.1:8080";
        }
    };
    const config = Config{
        .authority = &authority,
        .http_headers = .{ .user_agent = "Mozilla/5.0" },
    };

    const snapshot = fromConfigWithCurlAvailability(&config, false);

    try testing.expect(snapshot.canvas_profile_active);
    try testing.expect(snapshot.canvas_2d_profile_active);
    try testing.expect(snapshot.canvas_blob_profile_active);
    try testing.expect(snapshot.offscreen_canvas_profile_active);
    try testing.expect(snapshot.plugin_profile_active);
    try testing.expect(snapshot.plugin_mime_profile_active);
    try testing.expect(snapshot.chrome_profile_active);
    try testing.expect(snapshot.chrome_runtime_profile_active);
    try testing.expect(!snapshot.storage_profile_active);
    try testing.expect(snapshot.storage_estimate_profile_active);
    try testing.expect(!snapshot.storage_persistence_profile_active);
    try testing.expect(!snapshot.cache_storage_profile_active);
    try testing.expect(!snapshot.cache_storage_semantics_active);
    try testing.expect(!snapshot.file_system_profile_active);
    try testing.expect(!snapshot.file_system_semantics_active);
    try testing.expect(snapshot.webgl_profile_active);
    try testing.expect(snapshot.webgl_identity_profile_active);
    try testing.expect(snapshot.webgl_caps_profile_active);
    try testing.expect(!snapshot.audio_profile_active);
    try testing.expect(snapshot.audio_buffer_profile_active);
    try testing.expect(!snapshot.audio_graph_profile_active);
    try testing.expect(!snapshot.geolocation_profile_active);
    try testing.expect(!snapshot.geolocation_position_profile_active);
    try testing.expectEqual(@as(usize, 0), snapshot.degraded_capabilities.len);

    authority.profile.plugins.pdf_enabled = false;
    const disabled_plugins_snapshot = fromConfigWithCurlAvailability(&config, false);

    try testing.expect(disabled_plugins_snapshot.plugin_profile_active);
    try testing.expect(disabled_plugins_snapshot.plugin_mime_profile_active);
    try testing.expect(disabled_plugins_snapshot.chrome_profile_active);
    try testing.expect(disabled_plugins_snapshot.chrome_runtime_profile_active);
    try testing.expect(!disabled_plugins_snapshot.storage_profile_active);
    try testing.expect(disabled_plugins_snapshot.storage_estimate_profile_active);
    try testing.expect(!disabled_plugins_snapshot.storage_persistence_profile_active);
    try testing.expect(!disabled_plugins_snapshot.cache_storage_profile_active);
    try testing.expect(!disabled_plugins_snapshot.file_system_profile_active);
    try testing.expect(!disabled_plugins_snapshot.geolocation_profile_active);
    try testing.expectEqual(@as(usize, 0), disabled_plugins_snapshot.degraded_capabilities.len);

    authority.profile.capabilities.requires_webrtc_exit_ip = true;
    const webrtc_snapshot = fromConfigWithCurlAvailability(&config, false);

    try testing.expectEqual(@as(usize, 1), webrtc_snapshot.degraded_capabilities.len);
    try testing.expect(std.mem.eql(u8, "webrtc_exit_ip", webrtc_snapshot.degraded_capabilities[0]));

    authority.profile.webrtc = .{ .enabled = true, .exit_ip = "203.0.113.10" };
    const webrtc_candidate_snapshot = fromConfigWithCurlAvailability(&config, false);

    try testing.expect(webrtc_candidate_snapshot.webrtc_supported);
    try testing.expect(webrtc_candidate_snapshot.webrtc_candidate_profile_active);
    try testing.expect(webrtc_candidate_snapshot.webrtc_exit_ip_active);
    try testing.expectEqualStrings("203.0.113.10", webrtc_candidate_snapshot.webrtc_exit_ip.?);
    try testing.expectEqual(@as(usize, 0), webrtc_candidate_snapshot.degraded_capabilities.len);
}

test "Chimera Diagnostics reports profile evidence tiers" {
    try expectProfileEvidenceTiersForTest();
}
