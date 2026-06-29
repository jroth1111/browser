const js = @import("../../js/js.zig");
const AudioBuffer = @import("AudioBuffer.zig");
const AudioProfile = @import("AudioProfile.zig");
const Nodes = @import("AudioNodes.zig");

const AudioContext = @This();

pub const _prototype_root = true;

destination: Nodes.AudioDestinationNode = .{},

pub fn constructor(exec: *js.Execution) !*AudioContext {
    return exec._factory.create(AudioContext{});
}

pub fn getSampleRate(_: *const AudioContext) f64 {
    return 48000;
}

pub fn getCurrentTime(_: *const AudioContext) f64 {
    return 0;
}

pub fn getState(_: *const AudioContext) []const u8 {
    return "running";
}

pub fn getDestination(self: *AudioContext) *Nodes.AudioDestinationNode {
    return &self.destination;
}

pub fn createBuffer(_: *AudioContext, channels: u32, length: u32, sample_rate: f64, exec: *js.Execution) !*AudioBuffer {
    return AudioBuffer.init(channels, length, sample_rate, AudioProfile.seed(exec), exec);
}

pub fn createBufferSource(_: *AudioContext, exec: *js.Execution) !*Nodes.AudioBufferSourceNode {
    return exec._factory.create(Nodes.AudioBufferSourceNode{});
}

pub fn createOscillator(_: *AudioContext, exec: *js.Execution) !*Nodes.OscillatorNode {
    return exec._factory.create(try Nodes.OscillatorNode.init(exec));
}

pub fn createDynamicsCompressor(_: *AudioContext, exec: *js.Execution) !*Nodes.DynamicsCompressorNode {
    return exec._factory.create(try Nodes.DynamicsCompressorNode.init(exec));
}

pub fn createAnalyser(_: *AudioContext, exec: *js.Execution) !*Nodes.AnalyserNode {
    return exec._factory.create(Nodes.AnalyserNode{});
}

pub fn createGain(_: *AudioContext, exec: *js.Execution) !*Nodes.GainNode {
    return exec._factory.create(try Nodes.GainNode.init(exec));
}

pub fn createBiquadFilter(_: *AudioContext, exec: *js.Execution) !*Nodes.BiquadFilterNode {
    return exec._factory.create(try Nodes.BiquadFilterNode.init(exec));
}

pub fn createWaveShaper(_: *AudioContext, exec: *js.Execution) !*Nodes.WaveShaperNode {
    return exec._factory.create(Nodes.WaveShaperNode{});
}

pub fn @"resume"(_: *AudioContext, exec: *js.Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(js.Undefined{});
}

pub fn @"suspend"(_: *AudioContext, exec: *js.Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(js.Undefined{});
}

pub fn close(_: *AudioContext, exec: *js.Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(js.Undefined{});
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(AudioContext);

    pub const Meta = struct {
        pub const name = "AudioContext";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(AudioContext.constructor, .{});
    pub const sampleRate = bridge.accessor(AudioContext.getSampleRate, null, .{});
    pub const currentTime = bridge.accessor(AudioContext.getCurrentTime, null, .{});
    pub const state = bridge.accessor(AudioContext.getState, null, .{});
    pub const destination = bridge.accessor(AudioContext.getDestination, null, .{});
    pub const createBuffer = bridge.function(AudioContext.createBuffer, .{ .dom_exception = true });
    pub const createBufferSource = bridge.function(AudioContext.createBufferSource, .{});
    pub const createOscillator = bridge.function(AudioContext.createOscillator, .{});
    pub const createDynamicsCompressor = bridge.function(AudioContext.createDynamicsCompressor, .{});
    pub const createAnalyser = bridge.function(AudioContext.createAnalyser, .{});
    pub const createGain = bridge.function(AudioContext.createGain, .{});
    pub const createBiquadFilter = bridge.function(AudioContext.createBiquadFilter, .{});
    pub const createWaveShaper = bridge.function(AudioContext.createWaveShaper, .{});
    pub const @"resume" = bridge.function(AudioContext.@"resume", .{});
    pub const @"suspend" = bridge.function(AudioContext.@"suspend", .{});
    pub const close = bridge.function(AudioContext.close, .{});
};

const testing = @import("../../../testing.zig");
test "WebApi: AudioContext" {
    try testing.htmlRunner("audio/audio_context.html", .{});
}
