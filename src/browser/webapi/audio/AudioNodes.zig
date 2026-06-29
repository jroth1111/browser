const js = @import("../../js/js.zig");
const std = @import("std");

pub fn registerTypes() []const type {
    return &.{
        AudioDestinationNode,
        AudioBufferSourceNode,
        OscillatorNode,
        DynamicsCompressorNode,
        AnalyserNode,
        GainNode,
        BiquadFilterNode,
        WaveShaperNode,
        AudioParam,
    };
}

const AudioBuffer = @import("AudioBuffer.zig");

pub const AudioParam = struct {
    value: f64 = 0,

    pub fn getValue(self: *const AudioParam) f64 {
        return self.value;
    }

    pub fn setValue(self: *AudioParam, value: f64) void {
        self.value = value;
    }

    pub fn setValueAtTime(self: *AudioParam, value: f64, start_time: f64) *AudioParam {
        _ = start_time;
        self.value = value;
        return self;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(AudioParam);
        pub const Meta = struct {
            pub const name = "AudioParam";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const value = bridge.accessor(AudioParam.getValue, AudioParam.setValue, .{});
        pub const defaultValue = bridge.property(0, .{ .template = false });
        pub const minValue = bridge.property(-3.4028234663852886e38, .{ .template = false });
        pub const maxValue = bridge.property(3.4028234663852886e38, .{ .template = false });
        pub const automationRate = bridge.property("a-rate", .{ .template = false, .readonly = false });
        pub const setValueAtTime = bridge.function(AudioParam.setValueAtTime, .{});
    };
};

fn newParam(exec: *js.Execution, value: f64) !*AudioParam {
    return exec._factory.create(AudioParam{ .value = value });
}

pub const AudioDestinationNode = struct {
    _pad: bool = false,

    pub fn connect(_: *AudioDestinationNode, destination: js.Value) js.Value {
        return destination;
    }

    pub fn disconnect(_: *AudioDestinationNode) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(AudioDestinationNode);
        pub const Meta = struct {
            pub const name = "AudioDestinationNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const connect = bridge.function(AudioDestinationNode.connect, .{});
        pub const disconnect = bridge.function(AudioDestinationNode.disconnect, .{ .noop = true });
    };
};

pub const AudioBufferSourceNode = struct {
    buffer: ?*AudioBuffer = null,
    connected_to_destination: bool = false,
    started: bool = false,

    pub fn getBuffer(self: *const AudioBufferSourceNode) ?*AudioBuffer {
        return self.buffer;
    }

    pub fn setBuffer(self: *AudioBufferSourceNode, buffer: ?*AudioBuffer) void {
        self.buffer = buffer;
    }

    pub fn connect(self: *AudioBufferSourceNode, destination: js.Value) js.Value {
        if (asNode(AudioDestinationNode, destination) != null) {
            self.connected_to_destination = true;
        }
        return destination;
    }

    pub fn disconnect(_: *AudioBufferSourceNode) void {}
    pub fn start(self: *AudioBufferSourceNode, _: ?f64, _: ?f64, _: ?f64) void {
        self.started = true;
    }
    pub fn stop(self: *AudioBufferSourceNode, _: ?f64) void {
        self.started = false;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(AudioBufferSourceNode);
        pub const Meta = struct {
            pub const name = "AudioBufferSourceNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const buffer = bridge.accessor(AudioBufferSourceNode.getBuffer, AudioBufferSourceNode.setBuffer, .{ .null_as_undefined = true });
        pub const connect = bridge.function(AudioBufferSourceNode.connect, .{});
        pub const disconnect = bridge.function(AudioBufferSourceNode.disconnect, .{ .noop = true });
        pub const start = bridge.function(AudioBufferSourceNode.start, .{});
        pub const stop = bridge.function(AudioBufferSourceNode.stop, .{});
    };
};

pub const OscillatorNode = struct {
    frequency: *AudioParam,
    detune: *AudioParam,
    waveform: AudioBuffer.Waveform = .sine,
    connected_to_compressor: bool = false,
    connected_to_destination: bool = false,
    started: bool = false,

    pub fn init(exec: *js.Execution) !OscillatorNode {
        return .{
            .frequency = try newParam(exec, 440),
            .detune = try newParam(exec, 0),
        };
    }

    pub fn getFrequency(self: *OscillatorNode) *AudioParam {
        return self.frequency;
    }

    pub fn getDetune(self: *OscillatorNode) *AudioParam {
        return self.detune;
    }

    pub fn getType(self: *const OscillatorNode) []const u8 {
        return switch (self.waveform) {
            .sine => "sine",
            .square => "square",
            .sawtooth => "sawtooth",
            .triangle => "triangle",
        };
    }

    pub fn setType(self: *OscillatorNode, value: []const u8) void {
        if (std.mem.eql(u8, value, "sine")) {
            self.waveform = .sine;
        } else if (std.mem.eql(u8, value, "square")) {
            self.waveform = .square;
        } else if (std.mem.eql(u8, value, "sawtooth")) {
            self.waveform = .sawtooth;
        } else if (std.mem.eql(u8, value, "triangle")) {
            self.waveform = .triangle;
        }
    }

    pub fn connect(self: *OscillatorNode, destination: js.Value) js.Value {
        if (asNode(DynamicsCompressorNode, destination) != null) {
            self.connected_to_compressor = true;
        }
        if (asNode(AudioDestinationNode, destination) != null) {
            self.connected_to_destination = true;
        }
        return destination;
    }

    pub fn disconnect(_: *OscillatorNode) void {}
    pub fn start(self: *OscillatorNode, _: ?f64) void {
        self.started = true;
    }
    pub fn stop(self: *OscillatorNode, _: ?f64) void {
        self.started = false;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(OscillatorNode);
        pub const Meta = struct {
            pub const name = "OscillatorNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const @"type" = bridge.accessor(OscillatorNode.getType, OscillatorNode.setType, .{});
        pub const frequency = bridge.accessor(OscillatorNode.getFrequency, null, .{});
        pub const detune = bridge.accessor(OscillatorNode.getDetune, null, .{});
        pub const connect = bridge.function(OscillatorNode.connect, .{});
        pub const disconnect = bridge.function(OscillatorNode.disconnect, .{ .noop = true });
        pub const start = bridge.function(OscillatorNode.start, .{});
        pub const stop = bridge.function(OscillatorNode.stop, .{});
    };
};

pub const DynamicsCompressorNode = struct {
    threshold: *AudioParam,
    knee: *AudioParam,
    ratio: *AudioParam,
    attack: *AudioParam,
    release: *AudioParam,
    connected_to_destination: bool = false,

    pub fn init(exec: *js.Execution) !DynamicsCompressorNode {
        return .{
            .threshold = try newParam(exec, -24),
            .knee = try newParam(exec, 30),
            .ratio = try newParam(exec, 12),
            .attack = try newParam(exec, 0.003),
            .release = try newParam(exec, 0.25),
        };
    }

    pub fn getThreshold(self: *DynamicsCompressorNode) *AudioParam {
        return self.threshold;
    }

    pub fn getKnee(self: *DynamicsCompressorNode) *AudioParam {
        return self.knee;
    }

    pub fn getRatio(self: *DynamicsCompressorNode) *AudioParam {
        return self.ratio;
    }

    pub fn getAttack(self: *DynamicsCompressorNode) *AudioParam {
        return self.attack;
    }

    pub fn getRelease(self: *DynamicsCompressorNode) *AudioParam {
        return self.release;
    }

    pub fn connect(self: *DynamicsCompressorNode, destination: js.Value) js.Value {
        if (asNode(AudioDestinationNode, destination) != null) {
            self.connected_to_destination = true;
        }
        return destination;
    }

    pub fn disconnect(_: *DynamicsCompressorNode) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(DynamicsCompressorNode);
        pub const Meta = struct {
            pub const name = "DynamicsCompressorNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const threshold = bridge.accessor(DynamicsCompressorNode.getThreshold, null, .{});
        pub const knee = bridge.accessor(DynamicsCompressorNode.getKnee, null, .{});
        pub const ratio = bridge.accessor(DynamicsCompressorNode.getRatio, null, .{});
        pub const attack = bridge.accessor(DynamicsCompressorNode.getAttack, null, .{});
        pub const release = bridge.accessor(DynamicsCompressorNode.getRelease, null, .{});
        pub const connect = bridge.function(DynamicsCompressorNode.connect, .{});
        pub const disconnect = bridge.function(DynamicsCompressorNode.disconnect, .{ .noop = true });
    };
};

pub const AnalyserNode = struct {
    fft_size: u32 = 2048,
    min_decibels: f64 = -100,
    max_decibels: f64 = -30,
    smoothing_time_constant: f64 = 0.8,

    pub fn connect(_: *AnalyserNode, destination: js.Value) js.Value {
        return destination;
    }

    pub fn disconnect(_: *AnalyserNode) void {}

    pub fn getFftSize(self: *const AnalyserNode) u32 {
        return self.fft_size;
    }

    pub fn setFftSize(self: *AnalyserNode, value: u32) !void {
        if (!validFftSize(value)) return error.IndexSizeError;
        self.fft_size = value;
    }

    pub fn getFrequencyBinCount(self: *const AnalyserNode) u32 {
        return self.fft_size / 2;
    }

    pub fn getMinDecibels(self: *const AnalyserNode) f64 {
        return self.min_decibels;
    }

    pub fn setMinDecibels(self: *AnalyserNode, value: f64) !void {
        if (value >= self.max_decibels) return error.IndexSizeError;
        self.min_decibels = value;
    }

    pub fn getMaxDecibels(self: *const AnalyserNode) f64 {
        return self.max_decibels;
    }

    pub fn setMaxDecibels(self: *AnalyserNode, value: f64) !void {
        if (value <= self.min_decibels) return error.IndexSizeError;
        self.max_decibels = value;
    }

    pub fn getSmoothingTimeConstant(self: *const AnalyserNode) f64 {
        return self.smoothing_time_constant;
    }

    pub fn setSmoothingTimeConstant(self: *AnalyserNode, value: f64) !void {
        if (value < 0 or value > 1) return error.IndexSizeError;
        self.smoothing_time_constant = value;
    }

    pub fn getFloatFrequencyData(self: *const AnalyserNode, data: []f32) void {
        for (data, 0..) |*sample, i| {
            const bucket: f32 = @floatFromInt((i + @as(usize, self.fft_size)) % 97);
            sample.* = -100.0 + bucket * 0.25;
        }
    }

    pub fn getByteFrequencyData(self: *const AnalyserNode, data: []u8) void {
        for (data, 0..) |*sample, i| {
            sample.* = @intCast((i * 13 + @as(usize, self.fft_size)) % 256);
        }
    }

    pub fn getFloatTimeDomainData(_: *const AnalyserNode, data: []f32) void {
        for (data, 0..) |*sample, i| {
            sample.* = if (i % 2 == 0) 0.00012207031 else -0.00012207031;
        }
    }

    pub fn getByteTimeDomainData(_: *const AnalyserNode, data: []u8) void {
        for (data, 0..) |*sample, i| {
            sample.* = if (i % 2 == 0) 128 else 127;
        }
    }

    fn validFftSize(value: u32) bool {
        return value >= 32 and value <= 32768 and (value & (value - 1)) == 0;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(AnalyserNode);
        pub const Meta = struct {
            pub const name = "AnalyserNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const fftSize = bridge.accessor(AnalyserNode.getFftSize, AnalyserNode.setFftSize, .{ .dom_exception = true });
        pub const frequencyBinCount = bridge.accessor(AnalyserNode.getFrequencyBinCount, null, .{});
        pub const minDecibels = bridge.accessor(AnalyserNode.getMinDecibels, AnalyserNode.setMinDecibels, .{ .dom_exception = true });
        pub const maxDecibels = bridge.accessor(AnalyserNode.getMaxDecibels, AnalyserNode.setMaxDecibels, .{ .dom_exception = true });
        pub const smoothingTimeConstant = bridge.accessor(AnalyserNode.getSmoothingTimeConstant, AnalyserNode.setSmoothingTimeConstant, .{ .dom_exception = true });
        pub const connect = bridge.function(AnalyserNode.connect, .{});
        pub const disconnect = bridge.function(AnalyserNode.disconnect, .{ .noop = true });
        pub const getFloatFrequencyData = bridge.function(AnalyserNode.getFloatFrequencyData, .{});
        pub const getByteFrequencyData = bridge.function(AnalyserNode.getByteFrequencyData, .{});
        pub const getFloatTimeDomainData = bridge.function(AnalyserNode.getFloatTimeDomainData, .{});
        pub const getByteTimeDomainData = bridge.function(AnalyserNode.getByteTimeDomainData, .{});
    };
};

pub const GainNode = struct {
    gain: *AudioParam,
    connected_to_destination: bool = false,

    pub fn init(exec: *js.Execution) !GainNode {
        return .{ .gain = try newParam(exec, 1) };
    }

    pub fn getGain(self: *GainNode) *AudioParam {
        return self.gain;
    }

    pub fn connect(self: *GainNode, destination: js.Value) js.Value {
        if (asNode(AudioDestinationNode, destination) != null) {
            self.connected_to_destination = true;
        }
        return destination;
    }

    pub fn disconnect(_: *GainNode) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(GainNode);
        pub const Meta = struct {
            pub const name = "GainNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const gain = bridge.accessor(GainNode.getGain, null, .{});
        pub const connect = bridge.function(GainNode.connect, .{});
        pub const disconnect = bridge.function(GainNode.disconnect, .{ .noop = true });
    };
};

pub const BiquadFilterNode = struct {
    frequency: *AudioParam,
    detune: *AudioParam,
    Q: *AudioParam,
    gain: *AudioParam,

    pub fn init(exec: *js.Execution) !BiquadFilterNode {
        return .{
            .frequency = try newParam(exec, 350),
            .detune = try newParam(exec, 0),
            .Q = try newParam(exec, 1),
            .gain = try newParam(exec, 0),
        };
    }

    pub fn getFrequency(self: *BiquadFilterNode) *AudioParam {
        return self.frequency;
    }

    pub fn getDetune(self: *BiquadFilterNode) *AudioParam {
        return self.detune;
    }

    pub fn getQ(self: *BiquadFilterNode) *AudioParam {
        return self.Q;
    }

    pub fn getGain(self: *BiquadFilterNode) *AudioParam {
        return self.gain;
    }

    pub fn connect(_: *BiquadFilterNode, destination: js.Value) js.Value {
        return destination;
    }

    pub fn disconnect(_: *BiquadFilterNode) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(BiquadFilterNode);
        pub const Meta = struct {
            pub const name = "BiquadFilterNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const @"type" = bridge.property("lowpass", .{ .template = false, .readonly = false });
        pub const frequency = bridge.accessor(BiquadFilterNode.getFrequency, null, .{});
        pub const detune = bridge.accessor(BiquadFilterNode.getDetune, null, .{});
        pub const Q = bridge.accessor(BiquadFilterNode.getQ, null, .{});
        pub const gain = bridge.accessor(BiquadFilterNode.getGain, null, .{});
        pub const connect = bridge.function(BiquadFilterNode.connect, .{});
        pub const disconnect = bridge.function(BiquadFilterNode.disconnect, .{ .noop = true });
    };
};

pub const WaveShaperNode = struct {
    curve: ?js.Value.Global = null,
    connected_to_destination: bool = false,

    pub fn getCurve(self: *const WaveShaperNode) ?js.Value.Global {
        return self.curve;
    }

    pub fn setCurve(self: *WaveShaperNode, curve: ?js.Value.Global, exec: *js.Execution) !void {
        var persisted = curve;
        if (persisted) |*value| {
            if (!value.local(exec.js.local.?).isFloat32Array()) {
                value.deinit();
                return error.TypeError;
            }
        }
        if (self.curve) |*old| old.deinit();
        self.curve = persisted;
    }

    pub fn connect(self: *WaveShaperNode, destination: js.Value) js.Value {
        if (asNode(AudioDestinationNode, destination) != null) {
            self.connected_to_destination = true;
        }
        return destination;
    }

    pub fn disconnect(_: *WaveShaperNode) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(WaveShaperNode);
        pub const Meta = struct {
            pub const name = "WaveShaperNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const curve = bridge.accessor(WaveShaperNode.getCurve, WaveShaperNode.setCurve, .{});
        pub const oversample = bridge.property("none", .{ .template = false, .readonly = false });
        pub const connect = bridge.function(WaveShaperNode.connect, .{});
        pub const disconnect = bridge.function(WaveShaperNode.disconnect, .{ .noop = true });
    };
};

fn asNode(comptime T: type, value: js.Value) ?*T {
    return value.local.jsValueToZig(*T, value) catch null;
}
