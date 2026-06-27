const std = @import("std");

const libcurl = @import("../sys/libcurl.zig");

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
        const impersonation_active = target != null and libcurl.has_curl_impersonate;
        const canvas_profile_active = profile.canvas.enabled;

        return .{
            .authority_version = loaded.authority_version,
            .profile_schema_version = loaded.profile_schema_version,
            .profile_id = loaded.profile_id,
            .route_id = loaded.network.route_id,
            .proxy_configured = proxy_configured,
            .impersonation_target = target,
            .requires_curl_impersonate = requires_curl_impersonate,
            .curl_impersonate_available = libcurl.has_curl_impersonate,
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
        .curl_impersonate_available = libcurl.has_curl_impersonate,
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
