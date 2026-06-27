const js = @import("../../js/js.zig");
const AudioProfile = @import("AudioProfile.zig");

const Execution = js.Execution;

const AudioBuffer = @This();

pub const _prototype_root = true;

_number_of_channels: u32,
_length: u32,
_sample_rate: f64,
_seed: u64,

const ConstructorOptions = struct {
    length: u32,
    numberOfChannels: u32 = 1,
    sampleRate: f64,
};

pub fn constructor(options: ConstructorOptions, exec: *Execution) !*AudioBuffer {
    return init(options.numberOfChannels, options.length, options.sampleRate, AudioProfile.seed(exec), exec);
}

pub fn init(channels: u32, length: u32, sample_rate: f64, seed: u64, exec: *Execution) !*AudioBuffer {
    if (channels == 0 or channels > 32 or length == 0 or sample_rate <= 0) {
        return error.IndexSizeError;
    }
    return exec._factory.create(AudioBuffer{
        ._number_of_channels = channels,
        ._length = length,
        ._sample_rate = sample_rate,
        ._seed = seed,
    });
}

pub fn getLength(self: *const AudioBuffer) u32 {
    return self._length;
}

pub fn getDuration(self: *const AudioBuffer) f64 {
    return @as(f64, @floatFromInt(self._length)) / self._sample_rate;
}

pub fn getSampleRate(self: *const AudioBuffer) f64 {
    return self._sample_rate;
}

pub fn getNumberOfChannels(self: *const AudioBuffer) u32 {
    return self._number_of_channels;
}

pub fn getChannelData(self: *const AudioBuffer, channel: u32, exec: *Execution) !js.TypedArray(f32) {
    if (channel >= self._number_of_channels) return error.IndexSizeError;
    const out = try exec.call_arena.alloc(f32, self._length);
    fillSamples(out, self._seed, channel, 0);
    return .{ .values = out };
}

pub fn copyFromChannel(self: *const AudioBuffer, destination: []f32, channel: u32, start_in_channel: ?u32) !void {
    if (channel >= self._number_of_channels) return error.IndexSizeError;
    const start = start_in_channel orelse 0;
    if (start >= self._length) return;
    const available: usize = @intCast(self._length - start);
    fillSamples(destination[0..@min(destination.len, available)], self._seed, channel, start);
}

pub fn copyToChannel(_: *AudioBuffer, _: []f32, _: u32, _: ?u32) void {}

fn fillSamples(out: []f32, seed: u64, channel: u32, start: u32) void {
    for (out, 0..) |*value, offset| {
        value.* = AudioProfile.sample(seed, channel, start + @as(u32, @intCast(offset)));
    }
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(AudioBuffer);

    pub const Meta = struct {
        pub const name = "AudioBuffer";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(AudioBuffer.constructor, .{ .dom_exception = true });
    pub const length = bridge.accessor(AudioBuffer.getLength, null, .{});
    pub const duration = bridge.accessor(AudioBuffer.getDuration, null, .{});
    pub const sampleRate = bridge.accessor(AudioBuffer.getSampleRate, null, .{});
    pub const numberOfChannels = bridge.accessor(AudioBuffer.getNumberOfChannels, null, .{});
    pub const getChannelData = bridge.function(AudioBuffer.getChannelData, .{ .dom_exception = true });
    pub const copyFromChannel = bridge.function(AudioBuffer.copyFromChannel, .{ .dom_exception = true });
    pub const copyToChannel = bridge.function(AudioBuffer.copyToChannel, .{ .noop = true });
};
