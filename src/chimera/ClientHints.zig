const std = @import("std");

const Profile = @import("Profile.zig");

const Allocator = std.mem.Allocator;

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

const testing = std.testing;

test "chimera.ClientHints formats brand lists and quoted values" {
    const brands = &[_]Profile.Brand{
        .{ .brand = "Chromium", .version = "136" },
        .{ .brand = "Not.A/Brand", .version = "24" },
    };

    const value = try formatBrandListValue(testing.allocator, brands);
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("\"Chromium\";v=\"136\", \"Not.A/Brand\";v=\"24\"", value);

    const header = try formatBrandListHeader(testing.allocator, "Sec-CH-UA", brands);
    defer testing.allocator.free(header);
    try testing.expectEqualStrings("Sec-CH-UA: \"Chromium\";v=\"136\", \"Not.A/Brand\";v=\"24\"", header);

    const quoted = try formatQuotedValue(testing.allocator, "macOS");
    defer testing.allocator.free(quoted);
    try testing.expectEqualStrings("\"macOS\"", quoted);

    try testing.expectEqualStrings("?0", mobileValue(false));
    try testing.expectEqualStrings("?1", mobileValue(true));
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
