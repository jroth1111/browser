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
    canvas_profile_active: bool,
    audio_profile_active: bool,
    init_scripts_registered: bool = false,
    timezone_path: []const u8 = "runtime_probe",
    webrtc_supported: bool = false,
    webrtc_exit_ip_active: bool = false,
    webrtc_exit_ip: ?[]const u8 = null,
    degraded_capabilities: []const []const u8 = &.{},
};

pub fn fromConfig(config: anytype) Snapshot {
    const libcurl = @import("../sys/libcurl.zig");
    return fromConfigWithCurlAvailability(config, libcurl.has_curl_impersonate);
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
        const canvas_profile_active = profile.canvas.enabled;

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
            .plugin_profile_active = profile.plugins.pdf_enabled,
            .canvas_profile_active = canvas_profile_active,
            .audio_profile_active = profile.audio.enabled,
            .degraded_capabilities = degradedCapabilities(
                requires_curl_impersonate,
                impersonation_active,
                profile.canvas.enabled,
                canvas_profile_active,
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
        .canvas_profile_active = false,
        .audio_profile_active = false,
    };
}

fn degradedCapabilities(
    requires_curl_impersonate: bool,
    impersonation_active: bool,
    requires_canvas: bool,
    canvas_active: bool,
) []const []const u8 {
    const curl_degraded = requires_curl_impersonate and !impersonation_active;
    const canvas_degraded = requires_canvas and !canvas_active;
    if (curl_degraded and canvas_degraded) {
        return &.{ "curl_impersonate", "canvas" };
    }
    if (curl_degraded) {
        return &.{"curl_impersonate"};
    }
    if (canvas_degraded) {
        return &.{"canvas"};
    }
    return &.{};
}

test "Chimera Diagnostics reports profile-backed canvas active" {
    const testing = std.testing;
    const Authority = @import("Authority.zig");
    const Profile = @import("Profile.zig");

    const languages = [_][]const u8{ "en-AU", "en" };
    const brands = [_]Profile.Brand{.{ .brand = "Chromium", .version = "136" }};
    const full_version_list = [_]Profile.Brand{.{ .brand = "Chromium", .version = "136.0.0.0" }};
    const form_factor = [_][]const u8{"Desktop"};
    const authority = Authority{
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
    try testing.expectEqual(@as(usize, 0), snapshot.degraded_capabilities.len);
}
