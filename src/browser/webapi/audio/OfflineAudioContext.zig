const js = @import("../../js/js.zig");
const AudioBuffer = @import("AudioBuffer.zig");
const AudioProfile = @import("AudioProfile.zig");
const Nodes = @import("AudioNodes.zig");

const OfflineAudioContext = @This();

pub const _prototype_root = true;

number_of_channels: u32,
length: u32,
sample_rate: f64,
destination: Nodes.AudioDestinationNode = .{},

pub fn constructor(channels: u32, length: u32, sample_rate: f64, exec: *js.Execution) !*OfflineAudioContext {
    if (channels == 0 or channels > 32 or length == 0 or sample_rate <= 0) {
        return error.IndexSizeError;
    }
    return exec._factory.create(OfflineAudioContext{
        .number_of_channels = channels,
        .length = length,
        .sample_rate = sample_rate,
    });
}

pub fn getSampleRate(self: *const OfflineAudioContext) f64 {
    return self.sample_rate;
}

pub fn getCurrentTime(_: *const OfflineAudioContext) f64 {
    return 0;
}

pub fn getState(_: *const OfflineAudioContext) []const u8 {
    return "suspended";
}

pub fn getDestination(self: *OfflineAudioContext) *Nodes.AudioDestinationNode {
    return &self.destination;
}

pub fn createBuffer(self: *OfflineAudioContext, channels: u32, length: u32, sample_rate: f64, exec: *js.Execution) !*AudioBuffer {
    _ = self;
    return AudioBuffer.init(channels, length, sample_rate, AudioProfile.seed(exec), exec);
}

pub fn createBufferSource(_: *OfflineAudioContext, exec: *js.Execution) !*Nodes.AudioBufferSourceNode {
    return exec._factory.create(Nodes.AudioBufferSourceNode{});
}

pub fn createOscillator(_: *OfflineAudioContext, exec: *js.Execution) !*Nodes.OscillatorNode {
    return exec._factory.create(Nodes.OscillatorNode{});
}

pub fn createDynamicsCompressor(_: *OfflineAudioContext, exec: *js.Execution) !*Nodes.DynamicsCompressorNode {
    return exec._factory.create(Nodes.DynamicsCompressorNode{});
}

pub fn startRendering(self: *OfflineAudioContext, exec: *js.Execution) !js.Promise {
    const buffer = try AudioBuffer.init(
        self.number_of_channels,
        self.length,
        self.sample_rate,
        AudioProfile.seed(exec),
        exec,
    );
    return exec.js.local.?.resolvePromise(buffer);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(OfflineAudioContext);

    pub const Meta = struct {
        pub const name = "OfflineAudioContext";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(OfflineAudioContext.constructor, .{ .dom_exception = true });
    pub const sampleRate = bridge.accessor(OfflineAudioContext.getSampleRate, null, .{});
    pub const currentTime = bridge.accessor(OfflineAudioContext.getCurrentTime, null, .{});
    pub const state = bridge.accessor(OfflineAudioContext.getState, null, .{});
    pub const destination = bridge.accessor(OfflineAudioContext.getDestination, null, .{});
    pub const createBuffer = bridge.function(OfflineAudioContext.createBuffer, .{ .dom_exception = true });
    pub const createBufferSource = bridge.function(OfflineAudioContext.createBufferSource, .{});
    pub const createOscillator = bridge.function(OfflineAudioContext.createOscillator, .{});
    pub const createDynamicsCompressor = bridge.function(OfflineAudioContext.createDynamicsCompressor, .{});
    pub const startRendering = bridge.function(OfflineAudioContext.startRendering, .{});
};
