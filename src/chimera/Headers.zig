const std = @import("std");

const Profile = @import("Profile.zig");

const Allocator = std.mem.Allocator;

pub const Owned = struct {
    user_agent_header: [:0]const u8,
    accept_language_header: [:0]const u8,
    sec_ch_ua_header: [:0]const u8,
    sec_ch_ua_mobile_header: [:0]const u8,
    sec_ch_ua_platform_header: [:0]const u8,
    sec_ch_ua_full_version_header: [:0]const u8,
    sec_ch_ua_full_version_list_header: [:0]const u8,
    sec_ch_ua_arch_header: [:0]const u8,
    sec_ch_ua_bitness_header: [:0]const u8,
    sec_ch_ua_model_header: [:0]const u8,
    sec_ch_ua_platform_version_header: [:0]const u8,

    pub fn deinit(self: *const Owned, allocator: Allocator) void {
        allocator.free(self.sec_ch_ua_platform_version_header);
        allocator.free(self.sec_ch_ua_model_header);
        allocator.free(self.sec_ch_ua_bitness_header);
        allocator.free(self.sec_ch_ua_arch_header);
        allocator.free(self.sec_ch_ua_full_version_list_header);
        allocator.free(self.sec_ch_ua_full_version_header);
        allocator.free(self.sec_ch_ua_platform_header);
        allocator.free(self.sec_ch_ua_mobile_header);
        allocator.free(self.sec_ch_ua_header);
        allocator.free(self.accept_language_header);
        allocator.free(self.user_agent_header);
    }
};

pub fn init(allocator: Allocator, headers: *const Profile.Headers) !Owned {
    const user_agent_header = try format(allocator, "User-Agent", headers.user_agent);
    errdefer allocator.free(user_agent_header);

    const accept_language_header = try format(allocator, "Accept-Language", headers.accept_language);
    errdefer allocator.free(accept_language_header);

    const sec_ch_ua_header = try format(allocator, "Sec-CH-UA", headers.sec_ch_ua);
    errdefer allocator.free(sec_ch_ua_header);

    const sec_ch_ua_mobile_header = try format(allocator, "Sec-CH-UA-Mobile", headers.sec_ch_ua_mobile);
    errdefer allocator.free(sec_ch_ua_mobile_header);

    const sec_ch_ua_platform_header = try format(allocator, "Sec-CH-UA-Platform", headers.sec_ch_ua_platform);
    errdefer allocator.free(sec_ch_ua_platform_header);

    const sec_ch_ua_full_version_header = try format(allocator, "Sec-CH-UA-Full-Version", headers.sec_ch_ua_full_version);
    errdefer allocator.free(sec_ch_ua_full_version_header);

    const sec_ch_ua_full_version_list_header = try format(allocator, "Sec-CH-UA-Full-Version-List", headers.sec_ch_ua_full_version_list);
    errdefer allocator.free(sec_ch_ua_full_version_list_header);

    const sec_ch_ua_arch_header = try format(allocator, "Sec-CH-UA-Arch", headers.sec_ch_ua_arch);
    errdefer allocator.free(sec_ch_ua_arch_header);

    const sec_ch_ua_bitness_header = try format(allocator, "Sec-CH-UA-Bitness", headers.sec_ch_ua_bitness);
    errdefer allocator.free(sec_ch_ua_bitness_header);

    const sec_ch_ua_model_header = try format(allocator, "Sec-CH-UA-Model", headers.sec_ch_ua_model);
    errdefer allocator.free(sec_ch_ua_model_header);

    const sec_ch_ua_platform_version_header = try format(allocator, "Sec-CH-UA-Platform-Version", headers.sec_ch_ua_platform_version);
    errdefer allocator.free(sec_ch_ua_platform_version_header);

    return .{
        .user_agent_header = user_agent_header,
        .accept_language_header = accept_language_header,
        .sec_ch_ua_header = sec_ch_ua_header,
        .sec_ch_ua_mobile_header = sec_ch_ua_mobile_header,
        .sec_ch_ua_platform_header = sec_ch_ua_platform_header,
        .sec_ch_ua_full_version_header = sec_ch_ua_full_version_header,
        .sec_ch_ua_full_version_list_header = sec_ch_ua_full_version_list_header,
        .sec_ch_ua_arch_header = sec_ch_ua_arch_header,
        .sec_ch_ua_bitness_header = sec_ch_ua_bitness_header,
        .sec_ch_ua_model_header = sec_ch_ua_model_header,
        .sec_ch_ua_platform_version_header = sec_ch_ua_platform_version_header,
    };
}

fn format(allocator: Allocator, comptime name: []const u8, value: []const u8) ![:0]const u8 {
    return try std.fmt.allocPrintSentinel(allocator, name ++ ": {s}", .{value}, 0);
}

const testing = std.testing;

test "chimera.Headers.init formats every profile header" {
    var owned = try init(testing.allocator, &.{
        .user_agent = "Mozilla/5.0 Chimera/120",
        .accept_language = "en-US,en;q=0.9",
        .sec_ch_ua = "\"Chromium\";v=\"120\", \"Not?A_Brand\";v=\"8\"",
        .sec_ch_ua_mobile = "?0",
        .sec_ch_ua_platform = "\"macOS\"",
        .sec_ch_ua_full_version = "\"120.0.0.0\"",
        .sec_ch_ua_full_version_list = "\"Chromium\";v=\"120.0.0.0\", \"Not?A_Brand\";v=\"8.0.0.0\"",
        .sec_ch_ua_arch = "\"x86\"",
        .sec_ch_ua_bitness = "\"64\"",
        .sec_ch_ua_model = "\"\"",
        .sec_ch_ua_platform_version = "\"10.15.7\"",
    });
    defer owned.deinit(testing.allocator);

    try testing.expectEqualStrings("User-Agent: Mozilla/5.0 Chimera/120", owned.user_agent_header);
    try testing.expectEqualStrings("Accept-Language: en-US,en;q=0.9", owned.accept_language_header);
    try testing.expectEqualStrings("Sec-CH-UA: \"Chromium\";v=\"120\", \"Not?A_Brand\";v=\"8\"", owned.sec_ch_ua_header);
    try testing.expectEqualStrings("Sec-CH-UA-Mobile: ?0", owned.sec_ch_ua_mobile_header);
    try testing.expectEqualStrings("Sec-CH-UA-Platform: \"macOS\"", owned.sec_ch_ua_platform_header);
    try testing.expectEqualStrings("Sec-CH-UA-Full-Version: \"120.0.0.0\"", owned.sec_ch_ua_full_version_header);
    try testing.expectEqualStrings("Sec-CH-UA-Full-Version-List: \"Chromium\";v=\"120.0.0.0\", \"Not?A_Brand\";v=\"8.0.0.0\"", owned.sec_ch_ua_full_version_list_header);
    try testing.expectEqualStrings("Sec-CH-UA-Arch: \"x86\"", owned.sec_ch_ua_arch_header);
    try testing.expectEqualStrings("Sec-CH-UA-Bitness: \"64\"", owned.sec_ch_ua_bitness_header);
    try testing.expectEqualStrings("Sec-CH-UA-Model: \"\"", owned.sec_ch_ua_model_header);
    try testing.expectEqualStrings("Sec-CH-UA-Platform-Version: \"10.15.7\"", owned.sec_ch_ua_platform_version_header);
}
