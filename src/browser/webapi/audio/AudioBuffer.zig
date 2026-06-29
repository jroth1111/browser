const js = @import("../../js/js.zig");
const std = @import("std");
const AudioProfile = @import("AudioProfile.zig");

const Execution = js.Execution;

const AudioBuffer = @This();

pub const _prototype_root = true;

_number_of_channels: u32,
_length: u32,
_sample_rate: f64,
_seed: u64,
_samples: []f32,

pub const Waveform = enum {
    sine,
    square,
    sawtooth,
    triangle,
};

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
    const samples = try exec.arena.alloc(f32, try sampleLen(channels, length));
    var channel: u32 = 0;
    while (channel < channels) : (channel += 1) {
        fillSamples(channelData(samples, length, channel), seed, channel, 0);
    }
    return exec._factory.create(AudioBuffer{
        ._number_of_channels = channels,
        ._length = length,
        ._sample_rate = sample_rate,
        ._seed = seed,
        ._samples = samples,
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
    _ = exec;
    if (channel >= self._number_of_channels) return error.IndexSizeError;
    return .{ .values = channelData(self._samples, self._length, channel) };
}

pub fn copyFromChannel(self: *const AudioBuffer, destination: []f32, channel: u32, start_in_channel: ?u32) !void {
    if (channel >= self._number_of_channels) return error.IndexSizeError;
    const start = start_in_channel orelse 0;
    if (start >= self._length) return;
    const available: usize = @intCast(self._length - start);
    const source = channelData(self._samples, self._length, channel)[start..];
    @memcpy(destination[0..@min(destination.len, available)], source[0..@min(destination.len, available)]);
}

pub fn copyToChannel(self: *AudioBuffer, source: []f32, channel: u32, start_in_channel: ?u32) !void {
    if (channel >= self._number_of_channels) return error.IndexSizeError;
    const start = start_in_channel orelse 0;
    if (start >= self._length) return;
    const available: usize = @intCast(self._length - start);
    const destination = channelData(self._samples, self._length, channel)[start..];
    @memcpy(destination[0..@min(source.len, available)], source[0..@min(source.len, available)]);
}

pub fn renderOfflineGraph(self: *AudioBuffer, seed: u64, frequency: f64, gain: f32, waveform: Waveform) void {
    var channel: u32 = 0;
    while (channel < self._number_of_channels) : (channel += 1) {
        const out = channelData(self._samples, self._length, channel);
        for (out, 0..) |*value, offset| {
            value.* = graphSample(
                seed,
                channel,
                @intCast(offset),
                frequency,
                self._sample_rate,
                gain,
                waveform,
            );
        }
    }
}

fn sampleLen(channels: u32, length: u32) !usize {
    const len = try std.math.mul(u64, channels, length);
    if (len > std.math.maxInt(usize)) return error.Overflow;
    return @intCast(len);
}

fn channelData(samples: []f32, length: u32, channel: u32) []f32 {
    const start = @as(usize, @intCast(channel)) * @as(usize, @intCast(length));
    return samples[start..][0..@intCast(length)];
}

fn fillSamples(out: []f32, seed: u64, channel: u32, start: u32) void {
    for (out, 0..) |*value, offset| {
        value.* = AudioProfile.sample(seed, channel, start + @as(u32, @intCast(offset)));
    }
}

fn graphSample(seed: u64, channel: u32, index: u32, frequency_: f64, sample_rate: f64, gain: f32, waveform: Waveform) f32 {
    const nyquist = sample_rate / 2.0;
    const frequency = if (frequency_ > 0 and frequency_ < nyquist) frequency_ else 440.0;
    const seed_phase = @as(f64, @floatFromInt((seed ^ (@as(u64, channel) << 17)) & 0xffff)) / 65536.0;
    const cycles = (@as(f64, @floatFromInt(index)) * frequency / sample_rate) + seed_phase;
    const phase = cycles - @floor(cycles);
    const wave: f64 = switch (waveform) {
        .sine => std.math.sin(phase * 2.0 * std.math.pi),
        .square => if (phase < 0.5) @as(f64, 1.0) else @as(f64, -1.0),
        .sawtooth => phase * 2.0 - 1.0,
        .triangle => if (phase < 0.5) (phase * 4.0 - 1.0) else (3.0 - phase * 4.0),
    };
    const noise = @as(f64, @floatCast(AudioProfile.sample(seed, channel, index))) * 0.5;
    const amplitude = @max(0.0, @min(@as(f64, @floatCast(gain)), 1.0));
    const sample = wave * amplitude * 0.35 + noise;
    return @floatCast(@max(-1.0, @min(1.0, sample)));
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
    pub const copyToChannel = bridge.function(AudioBuffer.copyToChannel, .{ .dom_exception = true });
};
