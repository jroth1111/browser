const std = @import("std");

const CDP = @import("../CDP.zig");
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
    const authority = config.chimeraAuthority();
    const profile = if (authority) |loaded| &loaded.profile else null;
    const diagnostics = if (authority) |loaded| loaded.diagnostics else .{};
    const target = config.curlImpersonateTarget();
    const requires_curl_impersonate = if (profile) |p|
        p.capabilities.requires_curl_impersonate or
            p.transport.requires_curl_impersonate or
            diagnostics.requires_curl_impersonate
    else
        false;

    return cmd.sendResult(.{
        .authority_version = if (authority) |loaded| loaded.authority_version else null,
        .profile_id = if (authority) |loaded| loaded.profile_id else null,
        .proxy_configured = config.httpProxy() != null,
        .impersonation_target = target,
        .requires_curl_impersonate = requires_curl_impersonate,
        .curl_impersonate_available = libcurl.has_curl_impersonate,
        .impersonation_active = target != null and libcurl.has_curl_impersonate,
        .header_profile_active = if (profile) |p|
            std.mem.eql(u8, config.http_headers.user_agent, p.headers.user_agent)
        else
            false,
        .navigator_profile_active = profile != null,
        .uadata_profile_active = profile != null,
        .plugin_profile_active = if (profile) |p| p.plugins.pdf_enabled else false,
        .canvas_profile_active = if (profile) |p| p.canvas.enabled else false,
        .audio_profile_active = if (profile) |p| p.audio.enabled else false,
        .timezone_path = "runtime_probe",
        .webrtc_supported = false,
        .webrtc_exit_ip_active = false,
        .webrtc_exit_ip = null,
    }, .{});
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
        .impersonation_active = false,
        .header_profile_active = false,
        .navigator_profile_active = false,
        .uadata_profile_active = false,
        .plugin_profile_active = false,
        .canvas_profile_active = false,
        .audio_profile_active = false,
        .timezone_path = "runtime_probe",
        .webrtc_supported = false,
        .webrtc_exit_ip_active = false,
    }, .{ .id = 1 });
}
