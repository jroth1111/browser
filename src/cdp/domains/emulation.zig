// Copyright (C) 2023-2024  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const lp = @import("lightpanda");

const CDP = @import("../CDP.zig");
const Config = @import("../../Config.zig");
const HttpClient = @import("../../browser/HttpClient.zig");
const Http = @import("../../network/http.zig");

const log = lp.log;

pub fn processMessage(cmd: *CDP.Command) !void {
    const action = std.meta.stringToEnum(enum {
        setEmulatedMedia,
        setFocusEmulationEnabled,
        setDeviceMetricsOverride,
        clearDeviceMetricsOverride,
        setTouchEmulationEnabled,
        setUserAgentOverride,
    }, cmd.input.action) orelse return error.UnknownMethod;

    switch (action) {
        .setEmulatedMedia => return setEmulatedMedia(cmd),
        .setFocusEmulationEnabled => return setFocusEmulationEnabled(cmd),
        .setDeviceMetricsOverride => return setDeviceMetricsOverride(cmd),
        .clearDeviceMetricsOverride => return clearDeviceMetricsOverride(cmd),
        .setTouchEmulationEnabled => return setTouchEmulationEnabled(cmd),
        .setUserAgentOverride => return setUserAgentOverride(cmd),
    }
}

// TODO: noop method
fn setEmulatedMedia(cmd: *CDP.Command) !void {
    // const input = (try const incoming.params(struct {
    //     media: ?[]const u8 = null,
    //     features: ?[]struct{
    //         name: []const u8,
    //         value: [] const u8
    //     } = null,
    // })) orelse return error.InvalidParams;

    return cmd.sendResult(null, .{});
}

// TODO: noop method
fn setFocusEmulationEnabled(cmd: *CDP.Command) !void {
    // const input = (try const incoming.params(struct {
    //     enabled: bool,
    // })) orelse return error.InvalidParams;
    return cmd.sendResult(null, .{});
}

fn setDeviceMetricsOverride(cmd: *CDP.Command) !void {
    const params = (try cmd.params(struct {
        width: u32,
        height: u32,
        deviceScaleFactor: ?f64 = null,
        mobile: ?bool = null,
        scale: ?f64 = null,
        screenWidth: ?u32 = null,
        screenHeight: ?u32 = null,
    })) orelse return error.InvalidParams;

    // Not-yet-emulated parameters: accept them but warn so the caller knows
    // they are ignored.
    if (params.deviceScaleFactor) |v| {
        if (v != 0) log.warn(.not_implemented, "setDeviceMetricsOverride", .{
            .cdp_cmd = "Emulation.setDeviceMetricsOverride",
            .param = "deviceScaleFactor",
            .value = v,
        });
    }
    if (params.mobile) |v| {
        if (v) log.warn(.not_implemented, "setDeviceMetricsOverride", .{
            .cdp_cmd = "Emulation.setDeviceMetricsOverride",
            .param = "mobile",
            .value = v,
        });
    }
    if (params.scale) |v| {
        if (v != 0) log.warn(.not_implemented, "setDeviceMetricsOverride", .{
            .cdp_cmd = "Emulation.setDeviceMetricsOverride",
            .param = "scale",
            .value = v,
        });
    }
    if (params.screenWidth) |v| {
        if (v != 0) log.warn(.not_implemented, "setDeviceMetricsOverride", .{
            .cdp_cmd = "Emulation.setDeviceMetricsOverride",
            .param = "screenWidth",
            .value = v,
        });
    }
    if (params.screenHeight) |v| {
        if (v != 0) log.warn(.not_implemented, "setDeviceMetricsOverride", .{
            .cdp_cmd = "Emulation.setDeviceMetricsOverride",
            .param = "screenHeight",
            .value = v,
        });
    }

    // The override is stored on the Browser so it persists across page
    // navigations for the whole CDP connection.
    const browser = &cmd.cdp.browser;

    // CDP convention: a 0 width/height means "don't override that dimension",
    // so keep the current value for any dimension passed as 0.
    const current = browser.getViewport();
    browser.viewport_override = .{
        .width = if (params.width > 0) params.width else current.width,
        .height = if (params.height > 0) params.height else current.height,
    };

    return cmd.sendResult(null, .{});
}

fn clearDeviceMetricsOverride(cmd: *CDP.Command) !void {
    cmd.cdp.browser.viewport_override = null;
    return cmd.sendResult(null, .{});
}

// TODO: noop method
fn setTouchEmulationEnabled(cmd: *CDP.Command) !void {
    return cmd.sendResult(null, .{});
}

// Emulation.setUserAgentOverride is also called by Network.setUserAgentOverride
pub fn setUserAgentOverride(cmd: *CDP.Command) !void {
    const params = (try cmd.params(struct {
        userAgent: []const u8,
        acceptLanguage: ?[]const u8 = null,
        platform: ?[]const u8 = null,
        userAgentMetadata: ?HttpClient.UserAgentMetadata = null,
    })) orelse return error.InvalidParams;

    const bc = cmd.browser_context orelse return error.BrowserContextNotLoaded;
    const http_client = &cmd.cdp.browser.http_client;
    if (http_client.network.config.chimeraAuthority() != null) {
        return cmd.sendResult(null, .{});
    }

    const ua = params.userAgent;
    Config.validateUserAgent(ua) catch |err| switch (err) {
        error.NonPrintable => return cmd.sendError(-32602, "User agent contains non-printable characters", .{}),
        error.Reserved => {
            log.warn(.not_implemented, "Emulation.setUserAgentOverride", .{ .param = "userAgent", .value = ua, .info = "User agent must not contain Mozilla" });
            return cmd.sendResult(null, .{});
        },
    };

    try http_client.setUserAgentOverride(ua, params.acceptLanguage, params.platform, params.userAgentMetadata);
    bc.user_agent_changed = true;

    return cmd.sendResult(null, .{});
}

const testing = @import("../testing.zig");

test "cdp.Emulation: setUserAgentOverride with valid user agent" {
    var ctx = try testing.context();
    defer ctx.deinit();
    _ = try ctx.loadBrowserContext(.{ .id = "BID-UA1" });

    try ctx.processMessage(.{
        .id = 1,
        .method = "Emulation.setUserAgentOverride",
        .params = .{ .userAgent = "CustomBot/1.0" },
    });

    try ctx.expectSentResult(null, .{ .id = 1 });
}

test "cdp.Emulation: setUserAgentOverride ignores mozilla" {
    const filter: testing.LogFilter = .init(&.{.not_implemented});
    defer filter.deinit();

    var ctx = try testing.context();
    defer ctx.deinit();
    _ = try ctx.loadBrowserContext(.{ .id = "BID-UA2" });

    try ctx.processMessage(.{
        .id = 2,
        .method = "Emulation.setUserAgentOverride",
        .params = .{ .userAgent = "Mozilla/5.0 (Windows NT 10.0)" },
    });

    try ctx.expectSentResult(null, .{});
    try testing.expectEqual(false, ctx.cdp().browser_context.?.user_agent_changed);
}

test "cdp.Emulation: setUserAgentOverride ignores mozilla case insensitive" {
    const filter: testing.LogFilter = .init(&.{.not_implemented});
    defer filter.deinit();

    var ctx = try testing.context();
    defer ctx.deinit();
    _ = try ctx.loadBrowserContext(.{ .id = "BID-UA3" });

    try ctx.processMessage(.{
        .id = 3,
        .method = "Emulation.setUserAgentOverride",
        .params = .{ .userAgent = "MOZILLA/5.0 test" },
    });

    try ctx.expectSentResult(null, .{});
    try testing.expectEqual(false, ctx.cdp().browser_context.?.user_agent_changed);
}

test "cdp.Emulation: setUserAgentOverride rejects non-printable characters" {
    const filter: testing.LogFilter = .init(&.{.not_implemented});
    defer filter.deinit();

    var ctx = try testing.context();
    defer ctx.deinit();
    _ = try ctx.loadBrowserContext(.{ .id = "BID-UA4" });

    try ctx.processMessage(.{
        .id = 4,
        .method = "Emulation.setUserAgentOverride",
        .params = .{ .userAgent = "Bot/1.0\x01hidden" },
    });

    try ctx.expectSentError(-32602, "User agent contains non-printable characters", .{ .id = 4 });
}

test "cdp.Emulation: setUserAgentOverride with optional params" {
    var ctx = try testing.context();
    defer ctx.deinit();
    _ = try ctx.loadBrowserContext(.{ .id = "BID-UA5" });

    try ctx.processMessage(.{
        .id = 5,
        .method = "Emulation.setUserAgentOverride",
        .params = .{
            .userAgent = "CustomBot/2.0",
            .acceptLanguage = "en-US,en;q=0.9",
            .platform = "Linux",
            .userAgentMetadata = .{
                .brands = &.{
                    .{ .brand = "Chromium", .version = "136" },
                    .{ .brand = "Not.A/Brand", .version = "24" },
                },
                .fullVersionList = &.{
                    .{ .brand = "Chromium", .version = "136.0.0.0" },
                    .{ .brand = "Not.A/Brand", .version = "24.0.0.0" },
                },
                .fullVersion = "136.0.0.0",
                .platform = "Linux",
                .platformVersion = "6.6.0",
                .architecture = "x86",
                .bitness = "64",
                .model = "",
                .mobile = false,
                .wow64 = false,
                .formFactor = &.{"Desktop"},
            },
        },
    });

    try ctx.expectSentResult(null, .{ .id = 5 });

    const client = &ctx.cdp().browser.http_client;
    try testing.expectEqual("CustomBot/2.0", client.getUserAgent());
    try testing.expectEqual("en-US", client.getLanguageOverride().?);
    try testing.expectEqual("Linux", client.getNavigatorPlatformOverride().?);

    const languages = client.getLanguagesOverride().?;
    try testing.expectEqual(@as(usize, 2), languages.len);
    try testing.expectEqual("en-US", languages[0]);
    try testing.expectEqual("en", languages[1]);

    const ua_data = client.getUADataOverride().?;
    try testing.expectEqual(@as(usize, 2), ua_data.brands.len);
    try testing.expectEqual("Chromium", ua_data.brands[0].brand);
    try testing.expectEqual("136", ua_data.brands[0].version);
    try testing.expectEqual(@as(usize, 2), ua_data.full_version_list.len);
    try testing.expectEqual("136.0.0.0", ua_data.full_version_list[0].version);
    try testing.expectEqual(false, ua_data.mobile);
    try testing.expectEqual("Linux", ua_data.platform);
    try testing.expectEqual("x86", ua_data.architecture);
    try testing.expectEqual("64", ua_data.bitness);
    try testing.expectEqual("6.6.0", ua_data.platform_version);
    try testing.expectEqual("136.0.0.0", ua_data.ua_full_version);
    try testing.expectEqual("Desktop", ua_data.form_factor[0]);

    const headers = try client.newHeaders();
    defer headers.deinit();
    try expectRequestHeader(headers, "User-Agent", "CustomBot/2.0");
    try expectRequestHeader(headers, "Accept-Language", "en-US,en;q=0.9");
    try expectRequestHeader(headers, "Sec-CH-UA", "\"Chromium\";v=\"136\", \"Not.A/Brand\";v=\"24\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Mobile", "?0");
    try expectRequestHeader(headers, "Sec-CH-UA-Platform", "\"Linux\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Full-Version", "\"136.0.0.0\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Full-Version-List", "\"Chromium\";v=\"136.0.0.0\", \"Not.A/Brand\";v=\"24.0.0.0\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Arch", "\"x86\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Bitness", "\"64\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Model", "\"\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Platform-Version", "\"6.6.0\"");
}

test "cdp.Emulation: setUserAgentOverride can be called multiple times" {
    var ctx = try testing.context();
    defer ctx.deinit();
    _ = try ctx.loadBrowserContext(.{ .id = "BID-UA6" });

    try ctx.processMessage(.{
        .id = 6,
        .method = "Emulation.setUserAgentOverride",
        .params = .{ .userAgent = "FirstBot/1.0" },
    });

    try ctx.expectSentResult(null, .{ .id = 6 });

    try ctx.processMessage(.{
        .id = 7,
        .method = "Emulation.setUserAgentOverride",
        .params = .{ .userAgent = "SecondBot/2.0" },
    });

    try ctx.expectSentResult(null, .{ .id = 7 });
}

test "cdp.Emulation: setUserAgentOverride is ignored under Chimera authority" {
    var ctx = try testing.context();
    defer ctx.deinit();
    _ = try ctx.loadBrowserContext(.{ .id = "BID-UA7" });
    var guard = try ctx.enableManagedAuthority(testing.managedAuthority());
    defer guard.deinit();

    try ctx.processMessage(.{
        .id = 17,
        .method = "Emulation.setUserAgentOverride",
        .params = .{
            .userAgent = "CustomBot/9.0",
            .acceptLanguage = "fr-FR,fr;q=0.9",
            .platform = "Linux x86_64",
            .userAgentMetadata = .{
                .brands = &.{.{ .brand = "Chromium", .version = "999" }},
                .fullVersionList = &.{.{ .brand = "Chromium", .version = "999.0.0.0" }},
                .fullVersion = "999.0.0.0",
                .platform = "Linux",
                .platformVersion = "6.6.0",
                .architecture = "x86",
                .bitness = "64",
                .model = "",
                .mobile = false,
                .wow64 = false,
                .formFactor = &.{"Desktop"},
            },
        },
    });

    try ctx.expectSentResult(null, .{ .id = 17 });

    const client = &ctx.cdp().browser.http_client;
    try testing.expectEqual("Mozilla/5.0", client.getUserAgent());
    try testing.expect(client.getLanguageOverride() == null);
    try testing.expect(client.getNavigatorPlatformOverride() == null);
    try testing.expect(client.getUADataOverride() == null);
    try testing.expectEqual(false, ctx.cdp().browser_context.?.user_agent_changed);

    const headers = try client.newHeaders();
    defer headers.deinit();
    try expectRequestHeader(headers, "User-Agent", "Mozilla/5.0");
    try expectRequestHeader(headers, "Accept-Language", "en-AU,en;q=0.9");
    try expectRequestHeader(headers, "Sec-CH-UA", "\"Chromium\";v=\"136\"");
    try expectRequestHeader(headers, "Sec-CH-UA-Arch", "\"arm\"");
}

test "cdp.Emulation: setDeviceMetricsOverride and clear" {
    var ctx = try testing.context();
    defer ctx.deinit();

    const bc = try ctx.loadBrowserContext(.{ .id = "BID-DM1" });
    _ = try bc.session.createPage();
    const page = bc.mainPage().?;

    // Defaults to the compile-time viewport before any override.
    try testing.expectEqual(1920, page.getViewport().width);
    try testing.expectEqual(1080, page.getViewport().height);

    try ctx.processMessage(.{
        .id = 8,
        .method = "Emulation.setDeviceMetricsOverride",
        .params = .{ .width = 375, .height = 812 },
    });

    try ctx.expectSentResult(null, .{ .id = 8 });
    try testing.expectEqual(375, page.getViewport().width);
    try testing.expectEqual(812, page.getViewport().height);

    // The override lives on the Browser, so it persists across page
    // navigations rather than being lost with the page.
    try testing.expectEqual(375, bc.session.browser.getViewport().width);
    try testing.expectEqual(812, bc.session.browser.getViewport().height);

    try ctx.processMessage(.{
        .id = 9,
        .method = "Emulation.clearDeviceMetricsOverride",
    });

    try ctx.expectSentResult(null, .{ .id = 9 });
    try testing.expectEqual(1920, page.getViewport().width);
    try testing.expectEqual(1080, page.getViewport().height);
}

fn expectRequestHeader(headers: Http.Headers, name: []const u8, expected: []const u8) !void {
    var it = headers.iterator();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            return testing.expectEqual(expected, header.value);
        }
    }
    return testing.expect(false);
}
