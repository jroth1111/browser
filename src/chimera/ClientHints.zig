const std = @import("std");

const Profile = @import("Profile.zig");

const Allocator = std.mem.Allocator;

pub const sec_ch_ua_header_name = "Sec-CH-UA";
pub const sec_ch_ua_mobile_header_name = "Sec-CH-UA-Mobile";
pub const sec_ch_ua_platform_header_name = "Sec-CH-UA-Platform";
pub const sec_ch_ua_full_version_header_name = "Sec-CH-UA-Full-Version";
pub const sec_ch_ua_full_version_list_header_name = "Sec-CH-UA-Full-Version-List";
pub const sec_ch_ua_arch_header_name = "Sec-CH-UA-Arch";
pub const sec_ch_ua_bitness_header_name = "Sec-CH-UA-Bitness";
pub const sec_ch_ua_model_header_name = "Sec-CH-UA-Model";
pub const sec_ch_ua_platform_version_header_name = "Sec-CH-UA-Platform-Version";

pub const low_entropy_header_names = [_][]const u8{
    sec_ch_ua_header_name,
    sec_ch_ua_mobile_header_name,
    sec_ch_ua_platform_header_name,
};

pub const high_entropy_header_names = [_][]const u8{
    sec_ch_ua_full_version_header_name,
    sec_ch_ua_full_version_list_header_name,
    sec_ch_ua_arch_header_name,
    sec_ch_ua_bitness_header_name,
    sec_ch_ua_model_header_name,
    sec_ch_ua_platform_version_header_name,
};

pub fn isHighEntropyHeaderName(name: []const u8) bool {
    return containsHeaderName(high_entropy_header_names[0..], name);
}

pub fn isLowEntropyHeaderName(name: []const u8) bool {
    return containsHeaderName(low_entropy_header_names[0..], name);
}

pub fn formatBrandListValue(allocator: Allocator, brands: []const Profile.Brand) ![]const u8 {
    try validateBrandList(brands);

    var value = try std.ArrayList(u8).initCapacity(allocator, brands.len * 32);
    errdefer value.deinit(allocator);
    var writer = value.writer(allocator);

    for (brands, 0..) |brand, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.print("\"{s}\";v=\"{s}\"", .{ brand.brand, brand.version });
    }
    return try value.toOwnedSlice(allocator);
}

pub fn formatBrandListHeader(allocator: Allocator, comptime name: []const u8, brands: []const Profile.Brand) ![:0]const u8 {
    const value = try formatBrandListValue(allocator, brands);
    defer allocator.free(value);
    return try std.fmt.allocPrintSentinel(allocator, name ++ ": {s}", .{value}, 0);
}

pub fn formatQuotedValue(allocator: Allocator, value: []const u8) ![]const u8 {
    try validateStructuredString(value);
    return try std.fmt.allocPrint(allocator, "\"{s}\"", .{value});
}

pub fn formatQuotedHeader(allocator: Allocator, comptime name: []const u8, value: []const u8) ![:0]const u8 {
    try validateStructuredString(value);
    return try std.fmt.allocPrintSentinel(allocator, name ++ ": \"{s}\"", .{value}, 0);
}

pub fn mobileValue(mobile: bool) []const u8 {
    return if (mobile) "?1" else "?0";
}

pub fn formatMobileHeader(allocator: Allocator, comptime name: []const u8, mobile: bool) ![:0]const u8 {
    return try std.fmt.allocPrintSentinel(allocator, name ++ ": {s}", .{mobileValue(mobile)}, 0);
}

fn validateBrandList(brands: []const Profile.Brand) !void {
    for (brands) |brand| {
        if (brand.brand.len == 0 or brand.version.len == 0) {
            return error.InvalidClientHintValue;
        }
        try validateStructuredString(brand.brand);
        try validateStructuredString(brand.version);
    }
}

fn validateStructuredString(value: []const u8) !void {
    for (value) |ch| {
        if (!std.ascii.isPrint(ch) or ch == '"' or ch == '\\') {
            return error.InvalidClientHintValue;
        }
    }
}

fn containsHeaderName(candidates: []const []const u8, name: []const u8) bool {
    for (candidates) |candidate| {
        if (std.ascii.eqlIgnoreCase(candidate, name)) return true;
    }
    return false;
}

const testing = std.testing;

test "chimera.ClientHints formats brand lists and quoted values" {
    const brands = &[_]Profile.Brand{
        .{ .brand = "Chromium", .version = "136" },
        .{ .brand = "Not.A/Brand", .version = "24" },
    };

    const value = try formatBrandListValue(testing.allocator, brands);
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("\"Chromium\";v=\"136\", \"Not.A/Brand\";v=\"24\"", value);

    const header = try formatBrandListHeader(testing.allocator, sec_ch_ua_header_name, brands);
    defer testing.allocator.free(header);
    try testing.expectEqualStrings("Sec-CH-UA: \"Chromium\";v=\"136\", \"Not.A/Brand\";v=\"24\"", header);

    const quoted = try formatQuotedValue(testing.allocator, "macOS");
    defer testing.allocator.free(quoted);
    try testing.expectEqualStrings("\"macOS\"", quoted);

    try testing.expectEqualStrings("?0", mobileValue(false));
    try testing.expectEqualStrings("?1", mobileValue(true));
}

test "chimera.ClientHints classifies entropy-bearing headers" {
    try testing.expect(isLowEntropyHeaderName("sec-ch-ua"));
    try testing.expect(isLowEntropyHeaderName(sec_ch_ua_mobile_header_name));
    try testing.expect(!isLowEntropyHeaderName(sec_ch_ua_full_version_header_name));

    try testing.expect(isHighEntropyHeaderName("sec-ch-ua-full-version-list"));
    try testing.expect(isHighEntropyHeaderName(sec_ch_ua_platform_version_header_name));
    try testing.expect(!isHighEntropyHeaderName(sec_ch_ua_platform_header_name));
}

test "chimera.ClientHints rejects unsafe structured string values" {
    try testing.expectError(error.InvalidClientHintValue, formatQuotedValue(testing.allocator, "mac\"OS"));
    try testing.expectError(error.InvalidClientHintValue, formatQuotedValue(testing.allocator, "mac\\OS"));
    try testing.expectError(error.InvalidClientHintValue, formatQuotedValue(testing.allocator, "mac\nOS"));

    const brands = &[_]Profile.Brand{
        .{ .brand = "Chromium", .version = "136\r\nX-Bad: 1" },
    };
    try testing.expectError(error.InvalidClientHintValue, formatBrandListValue(testing.allocator, brands));

    const empty = &[_]Profile.Brand{
        .{ .brand = "", .version = "136" },
    };
    try testing.expectError(error.InvalidClientHintValue, formatBrandListValue(testing.allocator, empty));
}
