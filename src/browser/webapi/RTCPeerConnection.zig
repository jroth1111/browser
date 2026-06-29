const std = @import("std");

const js = @import("../js/js.zig");
const Seeds = @import("../../chimera/Seeds.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ RTCPeerConnection, RTCDataChannel };
}

const RTCPeerConnection = @This();

pub const _prototype_root = true;

local_description_set: bool = false,
remote_description_set: bool = false,
closed: bool = false,

const RTCSessionDescriptionInit = struct {
    type: []const u8,
    sdp: []const u8,
};

const RTCConfiguration = struct {};

const RTCStatsReport = struct {};

pub fn constructor(_: ?js.Value, exec: *Execution) !*RTCPeerConnection {
    if (!webrtcEnabled(exec)) return error.NotSupported;
    return exec._factory.create(RTCPeerConnection{});
}

pub fn createDataChannel(_: *RTCPeerConnection, label: []const u8, _: ?js.Value, exec: *Execution) !*RTCDataChannel {
    return exec._factory.create(RTCDataChannel{
        .label = try exec.dupeString(label),
    });
}

pub fn createOffer(_: *RTCPeerConnection, exec: *Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(try description("offer", exec));
}

pub fn createAnswer(_: *RTCPeerConnection, exec: *Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(try description("answer", exec));
}

pub fn setLocalDescription(self: *RTCPeerConnection, _: ?RTCSessionDescriptionInit, exec: *Execution) !js.Promise {
    self.local_description_set = true;
    return exec.js.local.?.resolvePromise(js.Undefined{});
}

pub fn setRemoteDescription(self: *RTCPeerConnection, _: ?RTCSessionDescriptionInit, exec: *Execution) !js.Promise {
    self.remote_description_set = true;
    return exec.js.local.?.resolvePromise(js.Undefined{});
}

pub fn addIceCandidate(_: *RTCPeerConnection, _: ?js.Value, exec: *Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(js.Undefined{});
}

pub fn getConfiguration(_: *const RTCPeerConnection) RTCConfiguration {
    return .{};
}

pub fn getStats(_: *const RTCPeerConnection, exec: *Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(RTCStatsReport{});
}

pub fn getLocalDescription(self: *RTCPeerConnection, exec: *Execution) !?RTCSessionDescriptionInit {
    if (!self.local_description_set) return null;
    return try description("offer", exec);
}

pub fn getRemoteDescription(self: *RTCPeerConnection, exec: *Execution) !?RTCSessionDescriptionInit {
    if (!self.remote_description_set) return null;
    return try description("answer", exec);
}

pub fn getCurrentLocalDescription(self: *RTCPeerConnection, exec: *Execution) !?RTCSessionDescriptionInit {
    return self.getLocalDescription(exec);
}

pub fn getCurrentRemoteDescription(self: *RTCPeerConnection, exec: *Execution) !?RTCSessionDescriptionInit {
    return self.getRemoteDescription(exec);
}

pub fn getPendingLocalDescription(_: *RTCPeerConnection) ?RTCSessionDescriptionInit {
    return null;
}

pub fn getPendingRemoteDescription(_: *RTCPeerConnection) ?RTCSessionDescriptionInit {
    return null;
}

pub fn getSignalingState(self: *const RTCPeerConnection) []const u8 {
    if (self.closed) return "closed";
    if (self.local_description_set and !self.remote_description_set) return "have-local-offer";
    if (self.remote_description_set and !self.local_description_set) return "have-remote-offer";
    return "stable";
}

pub fn getIceGatheringState(_: *const RTCPeerConnection) []const u8 {
    return "complete";
}

pub fn getIceConnectionState(self: *const RTCPeerConnection) []const u8 {
    return if (self.closed) "closed" else "new";
}

pub fn getConnectionState(self: *const RTCPeerConnection) []const u8 {
    return if (self.closed) "closed" else "new";
}

pub fn getCanTrickleIceCandidates(_: *const RTCPeerConnection) bool {
    return true;
}

pub fn getSenders(_: *const RTCPeerConnection) []const js.Value {
    return &.{};
}

pub fn getReceivers(_: *const RTCPeerConnection) []const js.Value {
    return &.{};
}

pub fn getTransceivers(_: *const RTCPeerConnection) []const js.Value {
    return &.{};
}

pub fn restartIce(_: *RTCPeerConnection) void {}

pub fn close(self: *RTCPeerConnection) void {
    self.closed = true;
}

fn description(kind: []const u8, exec: *Execution) !RTCSessionDescriptionInit {
    return .{
        .type = kind,
        .sdp = try sdp(exec),
    };
}

fn sdp(exec: *Execution) ![]const u8 {
    const ip = profileExitIp(exec);
    const seed = profileSeed(exec);
    const ufrag = Seeds.mix(seed, 0x574542525443);
    const pwd = Seeds.mix(seed, 0x4348494D455241);
    return std.fmt.allocPrint(
        exec.call_arena,
        "v=0\r\n" ++
            "o=- {d} 2 IN IP4 {s}\r\n" ++
            "s=-\r\n" ++
            "t=0 0\r\n" ++
            "a=group:BUNDLE 0\r\n" ++
            "a=msid-semantic: WMS\r\n" ++
            "m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n" ++
            "c=IN IP4 0.0.0.0\r\n" ++
            "a=mid:0\r\n" ++
            "a=sctp-port:5000\r\n" ++
            "a=ice-ufrag:{x}\r\n" ++
            "a=ice-pwd:{x}{x}\r\n" ++
            "a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\r\n" ++
            "a=setup:actpass\r\n" ++
            "a=candidate:1 1 udp 2122260223 {s} 9 typ host generation 0 network-id 1\r\n" ++
            "a=end-of-candidates\r\n",
        .{ seed, ip, ufrag, pwd, Seeds.mix(seed, 0x504153535744), ip },
    );
}

fn profileExitIp(exec: *const Execution) []const u8 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return "0.0.0.0";
    return exitIpForProfile(authority.profile.webrtc.enabled, authority.profile.webrtc.exit_ip);
}

fn webrtcEnabled(exec: *const Execution) bool {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return true;
    return authority.profile.webrtc.enabled;
}

fn exitIpForProfile(enabled: bool, exit_ip: ?[]const u8) []const u8 {
    if (!enabled) return "0.0.0.0";
    return exit_ip orelse "0.0.0.0";
}

fn profileSeed(exec: *const Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return 0xA57C51E8D00D1234;
    return Seeds.mix(authority.profile.seeds.human, authority.profile.seeds.canvas);
}

test "WebApi: RTCPeerConnection masks profile exit IP when WebRTC is disabled" {
    try std.testing.expectEqualStrings("0.0.0.0", exitIpForProfile(false, "203.0.113.10"));
    try std.testing.expectEqualStrings("0.0.0.0", exitIpForProfile(true, null));
    try std.testing.expectEqualStrings("203.0.113.10", exitIpForProfile(true, "203.0.113.10"));
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(RTCPeerConnection);

    pub const Meta = struct {
        pub const name = "RTCPeerConnection";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(RTCPeerConnection.constructor, .{ .dom_exception = true });
    pub const localDescription = bridge.accessor(RTCPeerConnection.getLocalDescription, null, .{ .null_as_undefined = true });
    pub const remoteDescription = bridge.accessor(RTCPeerConnection.getRemoteDescription, null, .{ .null_as_undefined = true });
    pub const currentLocalDescription = bridge.accessor(RTCPeerConnection.getCurrentLocalDescription, null, .{ .null_as_undefined = true });
    pub const currentRemoteDescription = bridge.accessor(RTCPeerConnection.getCurrentRemoteDescription, null, .{ .null_as_undefined = true });
    pub const pendingLocalDescription = bridge.accessor(RTCPeerConnection.getPendingLocalDescription, null, .{ .null_as_undefined = true });
    pub const pendingRemoteDescription = bridge.accessor(RTCPeerConnection.getPendingRemoteDescription, null, .{ .null_as_undefined = true });
    pub const signalingState = bridge.accessor(RTCPeerConnection.getSignalingState, null, .{});
    pub const iceGatheringState = bridge.accessor(RTCPeerConnection.getIceGatheringState, null, .{});
    pub const iceConnectionState = bridge.accessor(RTCPeerConnection.getIceConnectionState, null, .{});
    pub const connectionState = bridge.accessor(RTCPeerConnection.getConnectionState, null, .{});
    pub const canTrickleIceCandidates = bridge.accessor(RTCPeerConnection.getCanTrickleIceCandidates, null, .{});
    pub const createDataChannel = bridge.function(RTCPeerConnection.createDataChannel, .{});
    pub const createOffer = bridge.function(RTCPeerConnection.createOffer, .{});
    pub const createAnswer = bridge.function(RTCPeerConnection.createAnswer, .{});
    pub const setLocalDescription = bridge.function(RTCPeerConnection.setLocalDescription, .{});
    pub const setRemoteDescription = bridge.function(RTCPeerConnection.setRemoteDescription, .{});
    pub const addIceCandidate = bridge.function(RTCPeerConnection.addIceCandidate, .{});
    pub const getConfiguration = bridge.function(RTCPeerConnection.getConfiguration, .{});
    pub const getStats = bridge.function(RTCPeerConnection.getStats, .{});
    pub const getSenders = bridge.function(RTCPeerConnection.getSenders, .{});
    pub const getReceivers = bridge.function(RTCPeerConnection.getReceivers, .{});
    pub const getTransceivers = bridge.function(RTCPeerConnection.getTransceivers, .{});
    pub const restartIce = bridge.function(RTCPeerConnection.restartIce, .{});
    pub const close = bridge.function(RTCPeerConnection.close, .{});
};

const RTCDataChannel = struct {
    label: []const u8,
    ready_state: []const u8 = "open",

    pub fn getLabel(self: *const RTCDataChannel) []const u8 {
        return self.label;
    }

    pub fn getReadyState(self: *const RTCDataChannel) []const u8 {
        return self.ready_state;
    }

    pub fn send(_: *RTCDataChannel, _: js.Value) void {}

    pub fn close(self: *RTCDataChannel) void {
        self.ready_state = "closed";
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCDataChannel);

        pub const Meta = struct {
            pub const name = "RTCDataChannel";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const label = bridge.accessor(RTCDataChannel.getLabel, null, .{});
        pub const readyState = bridge.accessor(RTCDataChannel.getReadyState, null, .{});
        pub const send = bridge.function(RTCDataChannel.send, .{});
        pub const close = bridge.function(RTCDataChannel.close, .{});
    };
};
