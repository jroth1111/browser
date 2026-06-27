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
    const config = &cmd.cdp.browser.http_client.network.config;
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
        .impersonation_active = false,
        .header_profile_active = false,
        .navigator_profile_active = false,
        .uadata_profile_active = false,
        .plugin_profile_active = false,
        .canvas_profile_active = false,
        .audio_profile_active = false,
        .init_scripts_registered = false,
        .timezone_path = "runtime_probe",
        .webrtc_supported = false,
        .webrtc_exit_ip_active = false,
        .degraded_capabilities = &.{},
    }, .{ .id = 1 });
}
