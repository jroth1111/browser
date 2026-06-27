const js = @import("../../js/js.zig");

pub fn registerTypes() []const type {
    return &.{
        AudioDestinationNode,
        AudioBufferSourceNode,
        OscillatorNode,
        DynamicsCompressorNode,
        AudioParam,
    };
}

const AudioBuffer = @import("AudioBuffer.zig");

pub const AudioParam = struct {
    value: f64 = 0,

    pub fn constructor(value: ?f64, exec: *js.Execution) !*AudioParam {
        return exec._factory.create(AudioParam{ .value = value orelse 0 });
    }

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

        pub const constructor = bridge.constructor(AudioParam.constructor, .{});
        pub const value = bridge.accessor(AudioParam.getValue, AudioParam.setValue, .{});
        pub const defaultValue = bridge.property(0, .{ .template = false });
        pub const minValue = bridge.property(-3.4028234663852886e38, .{ .template = false });
        pub const maxValue = bridge.property(3.4028234663852886e38, .{ .template = false });
        pub const automationRate = bridge.property("a-rate", .{ .template = false, .readonly = false });
        pub const setValueAtTime = bridge.function(AudioParam.setValueAtTime, .{});
    };
};

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

    pub fn getBuffer(self: *const AudioBufferSourceNode) ?*AudioBuffer {
        return self.buffer;
    }

    pub fn setBuffer(self: *AudioBufferSourceNode, buffer: ?*AudioBuffer) void {
        self.buffer = buffer;
    }

    pub fn connect(_: *AudioBufferSourceNode, destination: js.Value) js.Value {
        return destination;
    }

    pub fn disconnect(_: *AudioBufferSourceNode) void {}
    pub fn start(_: *AudioBufferSourceNode, _: ?f64, _: ?f64, _: ?f64) void {}
    pub fn stop(_: *AudioBufferSourceNode, _: ?f64) void {}

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
        pub const start = bridge.function(AudioBufferSourceNode.start, .{ .noop = true });
        pub const stop = bridge.function(AudioBufferSourceNode.stop, .{ .noop = true });
    };
};

pub const OscillatorNode = struct {
    frequency: AudioParam = .{ .value = 440 },
    detune: AudioParam = .{},

    pub fn getFrequency(self: *OscillatorNode) *AudioParam {
        return &self.frequency;
    }

    pub fn getDetune(self: *OscillatorNode) *AudioParam {
        return &self.detune;
    }

    pub fn connect(_: *OscillatorNode, destination: js.Value) js.Value {
        return destination;
    }

    pub fn disconnect(_: *OscillatorNode) void {}
    pub fn start(_: *OscillatorNode, _: ?f64) void {}
    pub fn stop(_: *OscillatorNode, _: ?f64) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(OscillatorNode);
        pub const Meta = struct {
            pub const name = "OscillatorNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const @"type" = bridge.property("sine", .{ .template = false, .readonly = false });
        pub const frequency = bridge.accessor(OscillatorNode.getFrequency, null, .{});
        pub const detune = bridge.accessor(OscillatorNode.getDetune, null, .{});
        pub const connect = bridge.function(OscillatorNode.connect, .{});
        pub const disconnect = bridge.function(OscillatorNode.disconnect, .{ .noop = true });
        pub const start = bridge.function(OscillatorNode.start, .{ .noop = true });
        pub const stop = bridge.function(OscillatorNode.stop, .{ .noop = true });
    };
};

pub const DynamicsCompressorNode = struct {
    threshold: AudioParam = .{ .value = -24 },
    knee: AudioParam = .{ .value = 30 },
    ratio: AudioParam = .{ .value = 12 },
    attack: AudioParam = .{ .value = 0.003 },
    release: AudioParam = .{ .value = 0.25 },

    pub fn getThreshold(self: *DynamicsCompressorNode) *AudioParam {
        return &self.threshold;
    }

    pub fn getKnee(self: *DynamicsCompressorNode) *AudioParam {
        return &self.knee;
    }

    pub fn getRatio(self: *DynamicsCompressorNode) *AudioParam {
        return &self.ratio;
    }

    pub fn getAttack(self: *DynamicsCompressorNode) *AudioParam {
        return &self.attack;
    }

    pub fn getRelease(self: *DynamicsCompressorNode) *AudioParam {
        return &self.release;
    }

    pub fn connect(_: *DynamicsCompressorNode, destination: js.Value) js.Value {
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
