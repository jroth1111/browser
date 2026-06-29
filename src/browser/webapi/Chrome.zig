const std = @import("std");

const js = @import("../js/js.zig");
const Seeds = @import("../../chimera/Seeds.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ Chrome, ChromeRuntime, ChromeApp, ChromePort, ChromeEvent };
}

const Chrome = @This();

_runtime: ChromeRuntime = .{},
_app: ChromeApp = .{},

pub const init: Chrome = .{};

pub fn getRuntime(self: *Chrome) *ChromeRuntime {
    return &self._runtime;
}

pub fn getApp(self: *Chrome) *ChromeApp {
    return &self._app;
}

pub fn csi(_: *const Chrome) CsiResult {
    return .{};
}

pub fn loadTimes(_: *const Chrome) LoadTimesResult {
    return .{};
}

const CsiResult = struct {
    startE: f64 = 0,
    onloadT: f64 = 0,
    pageT: f64 = 0,
    tran: u32 = 15,
};

const LoadTimesResult = struct {
    requestTime: f64 = 0,
    startLoadTime: f64 = 0,
    commitLoadTime: f64 = 0,
    finishDocumentLoadTime: f64 = 0,
    finishLoadTime: f64 = 0,
    firstPaintTime: f64 = 0,
    firstPaintAfterLoadTime: f64 = 0,
    navigationType: []const u8 = "Other",
    wasFetchedViaSpdy: bool = false,
    wasNpnNegotiated: bool = false,
    npnNegotiatedProtocol: []const u8 = "unknown",
    connectionInfo: []const u8 = "unknown",
};

const ChromeRuntime = struct {
    _pad: bool = false,

    pub fn getId(_: *const ChromeRuntime, exec: *const Execution) []const u8 {
        const out = exec.call_arena.alloc(u8, 32) catch return fallback_runtime_id;
        var seed = runtimeSeed(exec);
        for (out, 0..) |*ch, index| {
            seed = Seeds.mix(seed, @intCast(index));
            ch.* = runtimeIdChar(@intCast((seed >> 60) & 0xF));
        }
        return out;
    }

    pub fn connect(_: *ChromeRuntime, _: []js.Value, exec: *Execution) !*ChromePort {
        return exec._factory.create(ChromePort{});
    }

    pub fn sendMessage(_: *ChromeRuntime, _: []js.Value) js.Undefined {
        return .{};
    }

    pub fn getManifest(_: *const ChromeRuntime) js.Undefined {
        return .{};
    }

    pub fn getURL(self: *const ChromeRuntime, path: []const u8, exec: *const Execution) ![]const u8 {
        const normalized = std.mem.trimLeft(u8, path, "/");
        return std.fmt.allocPrint(exec.call_arena, "chrome-extension://{s}/{s}", .{ self.getId(exec), normalized });
    }

    pub fn getPlatformInfo(_: *const ChromeRuntime, callback: ?js.Function, exec: *const Execution) !js.Undefined {
        if (callback) |cb| {
            try cb.call(void, .{chromePlatformInfo(exec)});
        }
        return .{};
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(ChromeRuntime);
        pub const Meta = struct {
            pub const name = "ChromeRuntime";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const id = bridge.accessor(ChromeRuntime.getId, null, .{});
        pub const connect = bridge.function(ChromeRuntime.connect, .{});
        pub const sendMessage = bridge.function(ChromeRuntime.sendMessage, .{});
        pub const getManifest = bridge.function(ChromeRuntime.getManifest, .{});
        pub const getURL = bridge.function(ChromeRuntime.getURL, .{});
        pub const getPlatformInfo = bridge.function(ChromeRuntime.getPlatformInfo, .{});
    };
};

const ChromePort = struct {
    _on_message: ChromeEvent = .{},
    _on_disconnect: ChromeEvent = .{},

    pub fn getName(_: *const ChromePort) []const u8 {
        return "";
    }

    pub fn getOnMessage(self: *ChromePort) *ChromeEvent {
        return &self._on_message;
    }

    pub fn getOnDisconnect(self: *ChromePort) *ChromeEvent {
        return &self._on_disconnect;
    }

    pub fn postMessage(_: *ChromePort, _: []js.Value) void {}
    pub fn disconnect(_: *ChromePort) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(ChromePort);
        pub const Meta = struct {
            pub const name = "ChromePort";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const name = bridge.accessor(ChromePort.getName, null, .{});
        pub const onMessage = bridge.accessor(ChromePort.getOnMessage, null, .{});
        pub const onDisconnect = bridge.accessor(ChromePort.getOnDisconnect, null, .{});
        pub const postMessage = bridge.function(ChromePort.postMessage, .{});
        pub const disconnect = bridge.function(ChromePort.disconnect, .{});
    };
};

const ChromeEvent = struct {
    _pad: bool = false,

    pub fn addListener(_: *ChromeEvent, _: ?js.Function) void {}
    pub fn removeListener(_: *ChromeEvent, _: ?js.Function) void {}
    pub fn hasListener(_: *const ChromeEvent, _: ?js.Function) bool {
        return false;
    }
    pub fn hasListeners(_: *const ChromeEvent) bool {
        return false;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(ChromeEvent);
        pub const Meta = struct {
            pub const name = "ChromeEvent";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const addListener = bridge.function(ChromeEvent.addListener, .{});
        pub const removeListener = bridge.function(ChromeEvent.removeListener, .{});
        pub const hasListener = bridge.function(ChromeEvent.hasListener, .{});
        pub const hasListeners = bridge.function(ChromeEvent.hasListeners, .{});
    };
};

const ChromePlatformInfo = struct {
    os: []const u8,
    arch: []const u8,
    nacl_arch: []const u8,
};

fn runtimeSeed(exec: *const Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return 0xD1B54A32D192ED03;
    return Seeds.mix(authority.profile.seeds.human, authority.profile.seeds.canvas);
}

fn chromePlatformInfo(exec: *const Execution) ChromePlatformInfo {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return .{
        .os = "mac",
        .arch = "x86-64",
        .nacl_arch = "x86-64",
    };
    const profile = authority.profile;
    return .{
        .os = chromeOs(profile.ua_data.platform),
        .arch = chromeArch(profile.ua_data.architecture),
        .nacl_arch = chromeArch(profile.ua_data.architecture),
    };
}

fn chromeOs(platform: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(platform, "macOS")) return "mac";
    if (std.ascii.eqlIgnoreCase(platform, "Windows")) return "win";
    if (std.ascii.eqlIgnoreCase(platform, "Android")) return "android";
    if (std.ascii.eqlIgnoreCase(platform, "Chrome OS")) return "cros";
    if (std.ascii.eqlIgnoreCase(platform, "Linux")) return "linux";
    return "mac";
}

fn chromeArch(architecture: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(architecture, "arm")) return "arm64";
    if (std.ascii.eqlIgnoreCase(architecture, "arm64")) return "arm64";
    if (std.ascii.eqlIgnoreCase(architecture, "x86")) return "x86-64";
    if (std.ascii.eqlIgnoreCase(architecture, "x86_64")) return "x86-64";
    return "x86-64";
}

const fallback_runtime_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const extension_id_alphabet = "abcdefghijklmnop";

fn runtimeIdChar(nibble: u4) u8 {
    return extension_id_alphabet[@intCast(nibble)];
}

test "WebApi: Chrome runtime ids use Chrome extension alphabet" {
    for (0..16) |index| {
        const ch = runtimeIdChar(@intCast(index));
        try std.testing.expect(ch >= 'a');
        try std.testing.expect(ch <= 'p');
    }
    for (fallback_runtime_id) |ch| {
        try std.testing.expect(ch >= 'a');
        try std.testing.expect(ch <= 'p');
    }
}

const ChromeApp = struct {
    _pad: bool = false,

    pub fn isInstalled(_: *const ChromeApp) bool {
        return false;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(ChromeApp);
        pub const Meta = struct {
            pub const name = "ChromeApp";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const isInstalled = bridge.accessor(ChromeApp.isInstalled, null, .{});
    };
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(Chrome);

    pub const Meta = struct {
        pub const name = "Chrome";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const runtime = bridge.accessor(Chrome.getRuntime, null, .{});
    pub const app = bridge.accessor(Chrome.getApp, null, .{});
    pub const csi = bridge.function(Chrome.csi, .{});
    pub const loadTimes = bridge.function(Chrome.loadTimes, .{});
};
