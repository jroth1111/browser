const Profile = @import("Profile.zig");

pub const Surface = enum {
    canvas,
    audio,
    font,
    human,
};

pub fn surfaceSeed(profile: *const Profile, surface: Surface) u64 {
    return switch (surface) {
        .canvas => profile.canvas.seed,
        .audio => profile.audio.seed,
        .font => profile.seeds.font,
        .human => profile.seeds.human,
    };
}

pub fn mix(seed: u64, value: u64) u64 {
    var x = seed ^ (value +% 0x9E3779B97F4A7C15);
    x = (x ^ (x >> 30)) *% 0xBF58476D1CE4E5B9;
    x = (x ^ (x >> 27)) *% 0x94D049BB133111EB;
    return x ^ (x >> 31);
}

pub fn byte(seed: u64, value: u64) u8 {
    return @truncate(mix(seed, value));
}

pub fn unitF32(seed: u64, value: u64) f32 {
    const raw: u32 = @truncate(mix(seed, value) >> 40);
    return @as(f32, @floatFromInt(raw)) / @as(f32, @floatFromInt(0xFFFFFF));
}

test "Chimera seeds are deterministic and separated" {
    const testing = @import("std").testing;

    try testing.expectEqual(byte(111, 1), byte(111, 1));
    try testing.expect(byte(111, 1) != byte(222, 1));
    try testing.expect(unitF32(111, 1) >= 0);
    try testing.expect(unitF32(111, 1) <= 1);
}
