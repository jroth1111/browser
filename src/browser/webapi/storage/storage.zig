// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const js = @import("../../js/js.zig");

const Allocator = std.mem.Allocator;

pub fn registerTypes() []const type {
    return &.{Lookup};
}

pub const Cookie = @import("Cookie.zig");

pub const Shed = struct {
    _origins: std.StringHashMapUnmanaged(*Bucket) = .empty,

    pub fn deinit(self: *Shed, allocator: Allocator) void {
        var it = self._origins.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            kv.value_ptr.*.deinit();
            allocator.destroy(kv.value_ptr.*);
        }
        self._origins.deinit(allocator);
    }

    pub fn getOrPut(self: *Shed, allocator: Allocator, origin: []const u8) !*Bucket {
        const gop = try self._origins.getOrPut(allocator, origin);
        if (gop.found_existing) return gop.value_ptr.*;
        errdefer std.debug.assert(self._origins.remove(origin));

        const bucket = try allocator.create(Bucket);
        errdefer allocator.destroy(bucket);
        bucket.* = .init(allocator);

        gop.key_ptr.* = try allocator.dupe(u8, origin);
        gop.value_ptr.* = bucket;
        return bucket;
    }
};

pub const Bucket = struct {
    _allocator: Allocator,
    local: Lookup,
    session: Lookup,
    caches: std.StringArrayHashMapUnmanaged(*CacheBucket) = .empty,

    pub fn init(allocator: Allocator) Bucket {
        return .{
            ._allocator = allocator,
            .local = .{ ._allocator = allocator },
            .session = .{ ._allocator = allocator },
        };
    }

    pub fn deinit(self: *Bucket) void {
        for (self.caches.keys(), self.caches.values()) |key, cache| {
            self._allocator.free(key);
            cache.deinit(self._allocator);
            self._allocator.destroy(cache);
        }
        self.caches.deinit(self._allocator);
        self.local.deinit();
        self.session.deinit();
    }

    pub fn openCache(self: *Bucket, name: []const u8) !void {
        if (self.caches.contains(name)) return;
        const owned = try self._allocator.dupe(u8, name);
        errdefer self._allocator.free(owned);
        const cache = try self._allocator.create(CacheBucket);
        errdefer self._allocator.destroy(cache);
        cache.* = .{};
        try self.caches.put(self._allocator, owned, cache);
    }

    pub fn hasCache(self: *const Bucket, name: []const u8) bool {
        return self.caches.contains(name);
    }

    pub fn getCache(self: *const Bucket, name: []const u8) ?*CacheBucket {
        return self.caches.get(name);
    }

    pub fn deleteCache(self: *Bucket, name: []const u8) bool {
        const index = self.caches.getIndex(name) orelse return false;
        const owned = self.caches.keys()[index];
        const cache = self.caches.values()[index];
        _ = self.caches.orderedRemove(name);
        cache.deinit(self._allocator);
        self._allocator.destroy(cache);
        self._allocator.free(owned);
        return true;
    }

    pub fn cacheNames(self: *const Bucket) []const []const u8 {
        return self.caches.keys();
    }

    pub fn matchCacheEntry(self: *const Bucket, request_url: []const u8) ?CachedResponse {
        for (self.caches.values()) |cache| {
            if (cache.match(request_url)) |entry| return entry;
        }
        return null;
    }
};

pub const CachedHeader = [2][]const u8;

pub const CachedResponse = struct {
    status: u16,
    status_text: []const u8,
    url: []const u8,
    body: []const u8,
    headers: []const CachedHeader,

    pub fn clone(self: CachedResponse, allocator: Allocator) !CachedResponse {
        const headers = try allocator.alloc(CachedHeader, self.headers.len);
        errdefer allocator.free(headers);
        var initialized: usize = 0;
        errdefer {
            for (headers[0..initialized]) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
        }
        for (self.headers, 0..) |pair, index| {
            const name = try allocator.dupe(u8, pair[0]);
            const value = allocator.dupe(u8, pair[1]) catch |err| {
                allocator.free(name);
                return err;
            };
            headers[index] = .{
                name,
                value,
            };
            initialized += 1;
        }
        const status_text = try allocator.dupe(u8, self.status_text);
        errdefer allocator.free(status_text);
        const url = try allocator.dupe(u8, self.url);
        errdefer allocator.free(url);
        const body = try allocator.dupe(u8, self.body);
        errdefer allocator.free(body);
        return .{
            .status = self.status,
            .status_text = status_text,
            .url = url,
            .body = body,
            .headers = headers,
        };
    }

    pub fn deinit(self: CachedResponse, allocator: Allocator) void {
        allocator.free(self.status_text);
        allocator.free(self.url);
        allocator.free(self.body);
        for (self.headers) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.headers);
    }
};

pub const CacheBucket = struct {
    entries: std.StringArrayHashMapUnmanaged(CachedResponse) = .empty,

    pub fn deinit(self: *CacheBucket, allocator: Allocator) void {
        for (self.entries.keys(), self.entries.values()) |key, response| {
            allocator.free(key);
            response.deinit(allocator);
        }
        self.entries.deinit(allocator);
    }

    pub fn put(self: *CacheBucket, allocator: Allocator, request_url: []const u8, response: CachedResponse) !void {
        const cloned = try response.clone(allocator);
        errdefer cloned.deinit(allocator);
        if (self.entries.getPtr(request_url)) |existing| {
            existing.deinit(allocator);
            existing.* = cloned;
            return;
        }
        const owned_url = try allocator.dupe(u8, request_url);
        errdefer allocator.free(owned_url);
        try self.entries.put(allocator, owned_url, cloned);
    }

    pub fn match(self: *const CacheBucket, request_url: []const u8) ?CachedResponse {
        return self.entries.get(request_url);
    }

    pub fn delete(self: *CacheBucket, allocator: Allocator, request_url: []const u8) bool {
        const index = self.entries.getIndex(request_url) orelse return false;
        const owned_url = self.entries.keys()[index];
        const response = self.entries.values()[index];
        _ = self.entries.orderedRemove(request_url);
        response.deinit(allocator);
        allocator.free(owned_url);
        return true;
    }

    pub fn requestUrls(self: *const CacheBucket) []const []const u8 {
        return self.entries.keys();
    }
};

pub const Lookup = struct {
    _data: std.StringHashMapUnmanaged([]const u8) = .empty,
    _size: usize = 0,
    _allocator: Allocator,

    const max_size = 5 * 1024 * 1024;

    pub fn deinit(self: *Lookup) void {
        var it = self._data.iterator();
        while (it.next()) |entry| {
            self._allocator.free(entry.key_ptr.*);
            self._allocator.free(entry.value_ptr.*);
        }
        self._data.deinit(self._allocator);
        self._size = 0;
    }

    pub fn getItem(self: *const Lookup, key_: ?[]const u8) ?[]const u8 {
        const k = key_ orelse return null;
        return self._data.get(k);
    }

    pub fn setItem(self: *Lookup, key_: ?[]const u8, value: []const u8) !void {
        const k = key_ orelse return;

        const old_len = if (self._data.get(k)) |old| old.len else 0;
        std.debug.assert(old_len <= self._size);
        if (self._size - old_len + value.len > max_size) {
            return error.QuotaExceeded;
        }

        if (self._data.getPtr(k)) |value_ptr| {
            const value_owned = try self._allocator.dupe(u8, value);
            self._size -= value_ptr.*.len;
            self._allocator.free(value_ptr.*);
            value_ptr.* = value_owned;
            self._size += value.len;
        } else {
            const key_owned = try self._allocator.dupe(u8, k);
            errdefer self._allocator.free(key_owned);
            const value_owned = try self._allocator.dupe(u8, value);
            errdefer self._allocator.free(value_owned);

            try self._data.put(self._allocator, key_owned, value_owned);
            self._size += value.len;
        }
    }

    pub fn removeItem(self: *Lookup, key_: ?[]const u8) void {
        const k = key_ orelse return;
        const kv = self._data.fetchRemove(k) orelse return;
        self._size -= kv.value.len;
        self._allocator.free(kv.key);
        self._allocator.free(kv.value);
    }

    pub fn clear(self: *Lookup) void {
        var it = self._data.iterator();
        while (it.next()) |entry| {
            self._allocator.free(entry.key_ptr.*);
            self._allocator.free(entry.value_ptr.*);
        }
        self._data.clearRetainingCapacity();
        self._size = 0;
    }

    pub fn key(self: *const Lookup, index: u32) ?[]const u8 {
        var it = self._data.keyIterator();
        var i: u32 = 0;
        while (it.next()) |k| {
            if (i == index) {
                return k.*;
            }
            i += 1;
        }
        return null;
    }

    pub fn getLength(self: *const Lookup) u32 {
        return @intCast(self._data.count());
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Lookup);

        pub const Meta = struct {
            pub const name = "Storage";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const length = bridge.accessor(Lookup.getLength, null, .{});
        pub const getItem = bridge.function(Lookup.getItem, .{});
        pub const setItem = bridge.function(Lookup.setItem, .{ .dom_exception = true });
        pub const removeItem = bridge.function(Lookup.removeItem, .{});
        pub const clear = bridge.function(Lookup.clear, .{});
        pub const key = bridge.function(Lookup.key, .{});
        pub const @"[str]" = bridge.namedIndexed(Lookup.getItem, Lookup.setItem, null, .{ .null_as_undefined = true });
    };
};

const testing = @import("../../../testing.zig");
test "WebApi: Storage" {
    try testing.htmlRunner("storage.html", .{});
}

test "WebApi: storage bucket tracks CacheStorage names" {
    var bucket = Bucket.init(testing.allocator);
    defer bucket.deinit();

    try std.testing.expect(!bucket.hasCache("asset-cache-a"));
    try bucket.openCache("asset-cache-a");
    try bucket.openCache("asset-cache-a");

    try std.testing.expect(bucket.hasCache("asset-cache-a"));
    try std.testing.expectEqual(@as(usize, 1), bucket.cacheNames().len);
    try std.testing.expectEqualStrings("asset-cache-a", bucket.cacheNames()[0]);
    try std.testing.expect(bucket.deleteCache("asset-cache-a"));
    try std.testing.expect(!bucket.deleteCache("asset-cache-a"));
    try std.testing.expectEqual(@as(usize, 0), bucket.cacheNames().len);
}

test "WebApi: storage bucket owns CacheStorage request entries" {
    var bucket = Bucket.init(testing.allocator);
    defer bucket.deinit();

    try bucket.openCache("asset-cache-a");
    const cache = bucket.getCache("asset-cache-a").?;
    try cache.put(testing.allocator, "https://example.test/a", .{
        .status = 203,
        .status_text = "Non-Authoritative Information",
        .url = "https://example.test/a",
        .body = "cached-body",
        .headers = &.{},
    });

    const matched = cache.match("https://example.test/a").?;
    try std.testing.expectEqual(@as(u16, 203), matched.status);
    try std.testing.expectEqualStrings("cached-body", matched.body);
    try std.testing.expectEqual(@as(usize, 1), cache.requestUrls().len);
    try std.testing.expectEqualStrings("https://example.test/a", cache.requestUrls()[0]);
    try std.testing.expect(bucket.matchCacheEntry("https://example.test/a") != null);
    try std.testing.expect(cache.delete(testing.allocator, "https://example.test/a"));
    try std.testing.expect(cache.match("https://example.test/a") == null);
}
