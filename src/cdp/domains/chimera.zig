const std = @import("std");

const CDP = @import("../CDP.zig");
const Diagnostics = @import("../../chimera/Diagnostics.zig");
const libcurl = @import("../../sys/libcurl.zig");

pub fn processMessage(cmd: *CDP.Command) !void {
    const action = std.meta.stringToEnum(enum {
        getProfileDiagnostics,
    }, cmd.input.action) orelse return error.UnknownMethod;

    switch (action) {
        .getProfileDiagnostics => return getProfileDiagnostics(cmd),
    }
}

fn getProfileDiagnostics(cmd: *CDP.Command) !void {
    const config = cmd.cdp.browser.http_client.network.config;
    return cmd.sendResult(Diagnostics.fromConfig(config), .{});
}

const testing = @import("../testing.zig");

test "cdp.Chimera: getProfileDiagnostics reports unmanaged defaults" {
    var ctx = try testing.context();
    defer ctx.deinit();

    try ctx.processMessage(.{
        .id = 1,
        .method = "Chimera.getProfileDiagnostics",
    });

    try ctx.expectSentResult(.{
        .proxy_configured = false,
        .requires_curl_impersonate = false,
        .curl_impersonate_available = libcurl.has_curl_impersonate,
        // Chrome TLS/JA3-JA4 impersonation is opt-out, not opt-in: with no
        // managed profile at all, this build still defaults to chrome136
        // whenever curl-impersonate is linked in (see
        // Config.default_curl_impersonate_target).
        .impersonation_target = if (libcurl.has_curl_impersonate) "chrome136" else null,
        .impersonation_active = libcurl.has_curl_impersonate,
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
        .timezone_profile_active = false,
        .init_scripts_registered = false,
        .timezone_path = "runtime_probe",
        .webrtc_supported = false,
        .webrtc_candidate_profile_active = false,
        .webrtc_exit_ip_active = false,
        .degraded_capabilities = &.{},
    }, .{ .id = 1 });
}
