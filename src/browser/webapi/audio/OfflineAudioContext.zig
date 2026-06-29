const js = @import("../../js/js.zig");
const AudioBuffer = @import("AudioBuffer.zig");
const AudioProfile = @import("AudioProfile.zig");
const Nodes = @import("AudioNodes.zig");
const log = @import("lightpanda").log;

const OfflineAudioContext = @This();

pub const _prototype_root = true;

number_of_channels: u32,
length: u32,
sample_rate: f64,
destination: Nodes.AudioDestinationNode = .{},
on_complete: ?js.Function.Global = null,
rendered_buffer: ?*AudioBuffer = null,
complete_dispatched: bool = false,
oscillator: ?*Nodes.OscillatorNode = null,
compressor: ?*Nodes.DynamicsCompressorNode = null,

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

pub fn createOscillator(self: *OfflineAudioContext, exec: *js.Execution) !*Nodes.OscillatorNode {
    const oscillator = try exec._factory.create(try Nodes.OscillatorNode.init(exec));
    self.oscillator = oscillator;
    return oscillator;
}

pub fn createDynamicsCompressor(self: *OfflineAudioContext, exec: *js.Execution) !*Nodes.DynamicsCompressorNode {
    const compressor = try exec._factory.create(try Nodes.DynamicsCompressorNode.init(exec));
    self.compressor = compressor;
    return compressor;
}

pub fn createAnalyser(_: *OfflineAudioContext, exec: *js.Execution) !*Nodes.AnalyserNode {
    return exec._factory.create(Nodes.AnalyserNode{});
}

pub fn createGain(_: *OfflineAudioContext, exec: *js.Execution) !*Nodes.GainNode {
    return exec._factory.create(try Nodes.GainNode.init(exec));
}

pub fn createBiquadFilter(_: *OfflineAudioContext, exec: *js.Execution) !*Nodes.BiquadFilterNode {
    return exec._factory.create(try Nodes.BiquadFilterNode.init(exec));
}

pub fn createWaveShaper(_: *OfflineAudioContext, exec: *js.Execution) !*Nodes.WaveShaperNode {
    return exec._factory.create(Nodes.WaveShaperNode{});
}

const FunctionSetter = union(enum) {
    func: js.Function.Global,
    anything: js.Value,
};

fn getFunctionFromSetter(setter_: ?FunctionSetter) ?js.Function.Global {
    const setter = setter_ orelse return null;
    return switch (setter) {
        .func => |func| func,
        .anything => null,
    };
}

pub fn getOnComplete(self: *const OfflineAudioContext) ?js.Function.Global {
    return self.on_complete;
}

pub fn setOnComplete(self: *OfflineAudioContext, setter: ?FunctionSetter, exec: *js.Execution) void {
    self.on_complete = getFunctionFromSetter(setter);
    if (self.rendered_buffer != null and !self.complete_dispatched) {
        self.dispatchComplete(exec) catch |err| {
            log.warn(.js, "OfflineAudioContext.oncomplete", .{ .err = err });
        };
    }
}

const OfflineAudioCompletionEvent = struct {
    renderedBuffer: *AudioBuffer,
};

pub fn startRendering(self: *OfflineAudioContext, exec: *js.Execution) !js.Promise {
    const seed = AudioProfile.seed(exec);
    const buffer = try AudioBuffer.init(
        self.number_of_channels,
        self.length,
        self.sample_rate,
        seed,
        exec,
    );
    if (self.graphRenderConfig()) |config| {
        buffer.renderOfflineGraph(seed, config.frequency, config.gain, config.waveform);
    }
    self.rendered_buffer = buffer;
    self.complete_dispatched = false;
    if (self.on_complete != null) {
        self.dispatchComplete(exec) catch |err| {
            log.warn(.js, "OfflineAudioContext.oncomplete", .{ .err = err });
        };
    }
    return exec.js.local.?.resolvePromise(buffer);
}

const GraphRenderConfig = struct {
    frequency: f64,
    gain: f32,
    waveform: AudioBuffer.Waveform,
};

fn graphRenderConfig(self: *const OfflineAudioContext) ?GraphRenderConfig {
    const oscillator = self.oscillator orelse return null;
    if (!oscillator.started) return null;

    const direct_destination = oscillator.connected_to_destination;
    const compressed_destination = if (self.compressor) |compressor|
        oscillator.connected_to_compressor and compressor.connected_to_destination
    else
        false;
    if (!direct_destination and !compressed_destination) return null;

    const compression_gain: f32 = if (compressed_destination) 0.72 else 1.0;
    return .{
        .frequency = oscillator.frequency.value,
        .gain = compression_gain,
        .waveform = oscillator.waveform,
    };
}

fn dispatchComplete(self: *OfflineAudioContext, exec: *js.Execution) !void {
    const callback = self.on_complete orelse return;
    const buffer = self.rendered_buffer orelse return;
    self.complete_dispatched = true;

    var ls: js.Local.Scope = undefined;
    exec.js.localScope(&ls);
    defer ls.deinit();

    try ls.toLocal(callback).call(void, .{OfflineAudioCompletionEvent{ .renderedBuffer = buffer }});
    ls.local.runMicrotasks();
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
    pub const oncomplete = bridge.accessor(OfflineAudioContext.getOnComplete, OfflineAudioContext.setOnComplete, .{});
    pub const createBuffer = bridge.function(OfflineAudioContext.createBuffer, .{ .dom_exception = true });
    pub const createBufferSource = bridge.function(OfflineAudioContext.createBufferSource, .{});
    pub const createOscillator = bridge.function(OfflineAudioContext.createOscillator, .{});
    pub const createDynamicsCompressor = bridge.function(OfflineAudioContext.createDynamicsCompressor, .{});
    pub const createAnalyser = bridge.function(OfflineAudioContext.createAnalyser, .{});
    pub const createGain = bridge.function(OfflineAudioContext.createGain, .{});
    pub const createBiquadFilter = bridge.function(OfflineAudioContext.createBiquadFilter, .{});
    pub const createWaveShaper = bridge.function(OfflineAudioContext.createWaveShaper, .{});
    pub const startRendering = bridge.function(OfflineAudioContext.startRendering, .{});
};
