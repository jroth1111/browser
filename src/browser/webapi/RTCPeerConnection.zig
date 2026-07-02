const std = @import("std");

const js = @import("../js/js.zig");
const Seeds = @import("../../chimera/Seeds.zig");

const EventTarget = @import("EventTarget.zig");
const Event = @import("Event.zig");
const RTCPeerConnectionIceEvent = @import("event/RTCPeerConnectionIceEvent.zig");

const Execution = js.Execution;
const Allocator = std.mem.Allocator;

pub fn registerTypes() []const type {
    return &.{ RTCPeerConnection, RTCDataChannel, RTCIceCandidate };
}

const RTCPeerConnection = @This();

_proto: *EventTarget,

local_description_set: bool = false,
remote_description_set: bool = false,
closed: bool = false,

// Real Chrome only starts ICE candidate gathering once a local description
// has been set (an ICE agent must not gather candidates prior to
// setLocalDescription, per the WebRTC spec), and gathering never restarts
// for the lifetime of this synthetic single-candidate connection.
_ice_gathering_state: IceGatheringState = .new,
_ice_gathering_started: bool = false,

_on_icecandidate: ?js.Function.Global = null,
_on_icecandidateerror: ?js.Function.Global = null,
_on_iceconnectionstatechange: ?js.Function.Global = null,
_on_icegatheringstatechange: ?js.Function.Global = null,
_on_connectionstatechange: ?js.Function.Global = null,
_on_signalingstatechange: ?js.Function.Global = null,
_on_negotiationneeded: ?js.Function.Global = null,
_on_datachannel: ?js.Function.Global = null,
_on_track: ?js.Function.Global = null,

const RTCSessionDescriptionInit = struct {
    type: []const u8,
    sdp: []const u8,
};

const RTCConfiguration = struct {};

const RTCStatsReport = struct {};

const IceGatheringState = enum {
    new,
    gathering,
    complete,

    fn toString(self: IceGatheringState) []const u8 {
        return switch (self) {
            .new => "new",
            .gathering => "gathering",
            .complete => "complete",
        };
    }
};

pub fn constructor(_: ?js.Value, exec: *Execution) !*RTCPeerConnection {
    if (!webrtcEnabled(exec)) return error.NotSupported;
    return exec._factory.eventTarget(RTCPeerConnection{
        ._proto = undefined,
    });
}

pub fn asEventTarget(self: *RTCPeerConnection) *EventTarget {
    return self._proto;
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
    try self.startIceGathering(exec);
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

pub fn getIceGatheringState(self: *const RTCPeerConnection) []const u8 {
    return self._ice_gathering_state.toString();
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

pub fn getOnIceCandidate(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_icecandidate;
}
pub fn setOnIceCandidate(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_icecandidate = cb;
}

pub fn getOnIceCandidateError(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_icecandidateerror;
}
pub fn setOnIceCandidateError(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_icecandidateerror = cb;
}

pub fn getOnIceConnectionStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_iceconnectionstatechange;
}
pub fn setOnIceConnectionStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_iceconnectionstatechange = cb;
}

pub fn getOnIceGatheringStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_icegatheringstatechange;
}
pub fn setOnIceGatheringStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_icegatheringstatechange = cb;
}

pub fn getOnConnectionStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_connectionstatechange;
}
pub fn setOnConnectionStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_connectionstatechange = cb;
}

pub fn getOnSignalingStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_signalingstatechange;
}
pub fn setOnSignalingStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_signalingstatechange = cb;
}

pub fn getOnNegotiationNeeded(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_negotiationneeded;
}
pub fn setOnNegotiationNeeded(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_negotiationneeded = cb;
}

pub fn getOnDataChannel(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_datachannel;
}
pub fn setOnDataChannel(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_datachannel = cb;
}

pub fn getOnTrack(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_track;
}
pub fn setOnTrack(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_track = cb;
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
    const candidate_attr = try iceCandidateAttr(exec.call_arena, ip);
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
            "a={s}\r\n" ++
            "a=end-of-candidates\r\n",
        .{ seed, ip, ufrag, pwd, Seeds.mix(seed, 0x504153535744), candidate_attr },
    );
}

// Shared source of truth for the fake host candidate: both the static SDP
// (`sdp()`, above) and the live `icecandidate` event dispatch (below) build
// this from the same declared profile exit IP, so nothing here ever gathers
// or exposes a real local/network address.
fn iceCandidateAttr(arena: Allocator, ip: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        arena,
        "candidate:1 1 udp 2122260223 {s} 9 typ host generation 0 network-id 1",
        .{ip},
    );
}

fn iceUfragHex(arena: Allocator, seed: u64) ![]const u8 {
    return std.fmt.allocPrint(arena, "{x}", .{Seeds.mix(seed, 0x574542525443)});
}

// Fires the real Chrome `icecandidate`/`icegatheringstatechange` sequence
// that RTCPeerConnection never dispatched before: gathering starts once a
// local description is set, one host candidate (derived from the same
// declared exit IP already baked into the SDP) is announced, then gathering
// completes and a final null-candidate `icecandidate` event signals
// end-of-candidates. Sites that wait for that null-candidate signal (the
// universal WebRTC IP-leak-detection pattern) would otherwise hang forever.
fn startIceGathering(self: *RTCPeerConnection, exec: *Execution) !void {
    if (self._ice_gathering_started or self.closed) {
        return;
    }
    self._ice_gathering_started = true;

    const target = self.asEventTarget();

    self._ice_gathering_state = .gathering;
    try self.dispatchIceGatheringStateChange(exec, target);

    const ip = profileExitIp(exec);
    const candidate = try exec._factory.create(RTCIceCandidate{
        ._candidate = try iceCandidateAttr(exec.arena, ip),
        ._address = ip,
        ._username_fragment = try iceUfragHex(exec.arena, profileSeed(exec)),
    });

    const candidate_event = try RTCPeerConnectionIceEvent.initTrusted(
        comptime .wrap("icecandidate"),
        .{ .candidate = candidate },
        exec.page,
    );
    try exec.dispatch(target, candidate_event.asEvent(), self._on_icecandidate, .{ .context = "RTCPeerConnection icecandidate" });

    // A listener may have closed the connection synchronously in response
    // to the candidate above; real Chrome fires no further events once closed.
    if (self.closed) {
        return;
    }

    self._ice_gathering_state = .complete;
    try self.dispatchIceGatheringStateChange(exec, target);

    const end_event = try RTCPeerConnectionIceEvent.initTrusted(
        comptime .wrap("icecandidate"),
        .{ .candidate = null },
        exec.page,
    );
    try exec.dispatch(target, end_event.asEvent(), self._on_icecandidate, .{ .context = "RTCPeerConnection icecandidate end-of-candidates" });
}

fn dispatchIceGatheringStateChange(self: *RTCPeerConnection, exec: *Execution, target: *EventTarget) !void {
    const event = try Event.initTrusted(.wrap("icegatheringstatechange"), .{}, exec.page);
    try exec.dispatch(target, event, self._on_icegatheringstatechange, .{ .context = "RTCPeerConnection icegatheringstatechange" });
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

const testing = @import("../../testing.zig");
test "WebApi: RTCPeerConnection" {
    try testing.htmlRunner("rtc_peer_connection.html", .{});
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(RTCPeerConnection);

    pub const Meta = struct {
        pub const name = "RTCPeerConnection";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const Prototype = EventTarget;

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

    pub const onicecandidate = bridge.accessor(RTCPeerConnection.getOnIceCandidate, RTCPeerConnection.setOnIceCandidate, .{});
    pub const onicecandidateerror = bridge.accessor(RTCPeerConnection.getOnIceCandidateError, RTCPeerConnection.setOnIceCandidateError, .{});
    pub const oniceconnectionstatechange = bridge.accessor(RTCPeerConnection.getOnIceConnectionStateChange, RTCPeerConnection.setOnIceConnectionStateChange, .{});
    pub const onicegatheringstatechange = bridge.accessor(RTCPeerConnection.getOnIceGatheringStateChange, RTCPeerConnection.setOnIceGatheringStateChange, .{});
    pub const onconnectionstatechange = bridge.accessor(RTCPeerConnection.getOnConnectionStateChange, RTCPeerConnection.setOnConnectionStateChange, .{});
    pub const onsignalingstatechange = bridge.accessor(RTCPeerConnection.getOnSignalingStateChange, RTCPeerConnection.setOnSignalingStateChange, .{});
    pub const onnegotiationneeded = bridge.accessor(RTCPeerConnection.getOnNegotiationNeeded, RTCPeerConnection.setOnNegotiationNeeded, .{});
    pub const ondatachannel = bridge.accessor(RTCPeerConnection.getOnDataChannel, RTCPeerConnection.setOnDataChannel, .{});
    pub const ontrack = bridge.accessor(RTCPeerConnection.getOnTrack, RTCPeerConnection.setOnTrack, .{});
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
        };

        pub const label = bridge.accessor(RTCDataChannel.getLabel, null, .{});
        pub const readyState = bridge.accessor(RTCDataChannel.getReadyState, null, .{});
        pub const send = bridge.function(RTCDataChannel.send, .{});
        pub const close = bridge.function(RTCDataChannel.close, .{});
    };
};

// The candidate carried by a real `icecandidate` event. Every dynamic field
// here (`_candidate`, `_address`, `_username_fragment`) is derived solely
// from the same declared profile exit IP / seed already used to build the
// static SDP in `sdp()` above - never a real local/network address.
pub const RTCIceCandidate = struct {
    _candidate: []const u8,
    _address: []const u8,
    _username_fragment: []const u8,
    _sdp_mid: []const u8 = "0",
    _sdp_m_line_index: u16 = 0,
    _foundation: []const u8 = "1",
    _component: []const u8 = "rtp",
    _priority: u32 = 2122260223,
    _protocol: []const u8 = "udp",
    _port: u16 = 9,
    _type: []const u8 = "host",

    pub fn getCandidate(self: *const RTCIceCandidate) []const u8 {
        return self._candidate;
    }

    pub fn getAddress(self: *const RTCIceCandidate) []const u8 {
        return self._address;
    }

    pub fn getUsernameFragment(self: *const RTCIceCandidate) []const u8 {
        return self._username_fragment;
    }

    pub fn getSdpMid(self: *const RTCIceCandidate) []const u8 {
        return self._sdp_mid;
    }

    pub fn getSdpMLineIndex(self: *const RTCIceCandidate) u16 {
        return self._sdp_m_line_index;
    }

    pub fn getFoundation(self: *const RTCIceCandidate) []const u8 {
        return self._foundation;
    }

    pub fn getComponent(self: *const RTCIceCandidate) []const u8 {
        return self._component;
    }

    pub fn getPriority(self: *const RTCIceCandidate) u32 {
        return self._priority;
    }

    pub fn getProtocol(self: *const RTCIceCandidate) []const u8 {
        return self._protocol;
    }

    pub fn getPort(self: *const RTCIceCandidate) u16 {
        return self._port;
    }

    pub fn getType(self: *const RTCIceCandidate) []const u8 {
        return self._type;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCIceCandidate);

        pub const Meta = struct {
            pub const name = "RTCIceCandidate";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const candidate = bridge.accessor(RTCIceCandidate.getCandidate, null, .{});
        pub const address = bridge.accessor(RTCIceCandidate.getAddress, null, .{});
        pub const usernameFragment = bridge.accessor(RTCIceCandidate.getUsernameFragment, null, .{});
        pub const sdpMid = bridge.accessor(RTCIceCandidate.getSdpMid, null, .{});
        pub const sdpMLineIndex = bridge.accessor(RTCIceCandidate.getSdpMLineIndex, null, .{});
        pub const foundation = bridge.accessor(RTCIceCandidate.getFoundation, null, .{});
        pub const component = bridge.accessor(RTCIceCandidate.getComponent, null, .{});
        pub const priority = bridge.accessor(RTCIceCandidate.getPriority, null, .{});
        pub const protocol = bridge.accessor(RTCIceCandidate.getProtocol, null, .{});
        pub const port = bridge.accessor(RTCIceCandidate.getPort, null, .{});
        pub const @"type" = bridge.accessor(RTCIceCandidate.getType, null, .{});
    };
};
