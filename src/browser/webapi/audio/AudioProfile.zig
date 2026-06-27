const js = @import("../../js/js.zig");
const Seeds = @import("../../../chimera/Seeds.zig");

const Execution = js.Execution;

pub fn seed(exec: *const Execution) u64 {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return 0;
    if (!authority.profile.audio.enabled) return 0;
    return Seeds.surfaceSeed(&authority.profile, .audio);
}

pub fn sample(seed_value: u64, channel: u32, index: u32) f32 {
    const mixed = Seeds.unitF32(seed_value, (@as(u64, channel) << 32) | index);
    return (mixed - 0.5) * 0.002;
}
