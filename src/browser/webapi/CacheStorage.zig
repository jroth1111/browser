// Copyright (C) 2026 Lightpanda (Selecy SAS)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

const js = @import("../js/js.zig");
const storage = @import("storage/storage.zig");

const Request = @import("net/Request.zig");
const Response = @import("net/Response.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ CacheStorage, Cache };
}

const CacheStorage = @This();

_pad: bool = false,

pub fn match(_: *const CacheStorage, request: js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
    const local = exec.js.local.?;
    const request_url = try requestUrl(request, exec);
    const cached = bucketForOrigin(exec).matchCacheEntry(request_url) orelse {
        return local.resolvePromise(js.Undefined{});
    };
    return local.resolvePromise(try Response.fromCacheSnapshot(&cached, exec));
}

pub fn has(_: *const CacheStorage, name: []const u8, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(bucketForOrigin(exec).hasCache(name));
}

pub fn open(_: *const CacheStorage, name: []const u8, exec: *const Execution) !js.Promise {
    try bucketForOrigin(exec).openCache(name);
    const cache = try exec._factory.create(Cache{
        ._name = try exec.dupeString(name),
    });
    return exec.js.local.?.resolvePromise(cache);
}

pub fn delete(_: *const CacheStorage, name: []const u8, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(bucketForOrigin(exec).deleteCache(name));
}

pub fn keys(_: *const CacheStorage, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(bucketForOrigin(exec).cacheNames());
}

const Cache = struct {
    _name: []const u8 = "",

    pub fn match(self: *const Cache, request: js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        const local = exec.js.local.?;
        const cache = bucketForOrigin(exec).getCache(self._name) orelse {
            return local.resolvePromise(js.Undefined{});
        };
        const request_url = try requestUrl(request, exec);
        const cached = cache.match(request_url) orelse {
            return local.resolvePromise(js.Undefined{});
        };
        return local.resolvePromise(try Response.fromCacheSnapshot(&cached, exec));
    }

    pub fn matchAll(self: *const Cache, request_: ?js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        const cache = bucketForOrigin(exec).getCache(self._name) orelse {
            const empty = [_]*Response{};
            return exec.js.local.?.resolvePromise(empty[0..]);
        };
        if (request_) |request| {
            const request_url = try requestUrl(request, exec);
            if (cache.match(request_url)) |cached| {
                const responses = try exec.call_arena.alloc(*Response, 1);
                responses[0] = try Response.fromCacheSnapshot(&cached, exec);
                return exec.js.local.?.resolvePromise(responses);
            }
            const empty = [_]*Response{};
            return exec.js.local.?.resolvePromise(empty[0..]);
        }
        const responses = try exec.call_arena.alloc(*Response, cache.entries.values().len);
        for (cache.entries.values(), 0..) |*cached, index| {
            responses[index] = try Response.fromCacheSnapshot(cached, exec);
        }
        return exec.js.local.?.resolvePromise(responses);
    }

    pub fn add(_: *const Cache, _: js.Value, exec: *const Execution) !js.Promise {
        return exec.js.local.?.resolvePromise(js.Undefined{});
    }

    pub fn addAll(_: *const Cache, _: []js.Value, exec: *const Execution) !js.Promise {
        return exec.js.local.?.resolvePromise(js.Undefined{});
    }

    pub fn put(self: *const Cache, request: js.Value, response: *Response, exec: *const Execution) !js.Promise {
        const bucket = bucketForOrigin(exec);
        const cache = bucket.getCache(self._name) orelse blk: {
            try bucket.openCache(self._name);
            break :blk bucket.getCache(self._name).?;
        };
        const request_url = try requestUrl(request, exec);
        var snapshot = try response.snapshotForCache(bucket._allocator);
        defer snapshot.deinit(bucket._allocator);
        try cache.put(bucket._allocator, request_url, snapshot);
        return exec.js.local.?.resolvePromise(js.Undefined{});
    }

    pub fn delete(self: *const Cache, request: js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        const bucket = bucketForOrigin(exec);
        const cache = bucket.getCache(self._name) orelse {
            return exec.js.local.?.resolvePromise(false);
        };
        const request_url = try requestUrl(request, exec);
        return exec.js.local.?.resolvePromise(cache.delete(bucket._allocator, request_url));
    }

    pub fn keys(self: *const Cache, _: ?js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        const cache = bucketForOrigin(exec).getCache(self._name) orelse {
            const empty = [_]*Request{};
            return exec.js.local.?.resolvePromise(empty[0..]);
        };
        const urls = cache.requestUrls();
        const requests = try exec.call_arena.alloc(*Request, urls.len);
        for (urls, 0..) |url, index| {
            requests[index] = try requestFromUrl(url, exec);
        }
        return exec.js.local.?.resolvePromise(requests);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Cache);

        pub const Meta = struct {
            pub const name = "Cache";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const match = bridge.function(Cache.match, .{});
        pub const matchAll = bridge.function(Cache.matchAll, .{});
        pub const add = bridge.function(Cache.add, .{});
        pub const addAll = bridge.function(Cache.addAll, .{});
        pub const put = bridge.function(Cache.put, .{});
        pub const delete = bridge.function(Cache.delete, .{});
        pub const keys = bridge.function(Cache.keys, .{});
    };
};

fn bucketForOrigin(exec: *const Execution) *storage.Bucket {
    return exec.session.storage_shed.getOrPut(
        exec.session.browser.app.allocator,
        exec.js.origin.key,
    ) catch @panic("OOM");
}

fn requestFromUrl(url: []const u8, exec: *const Execution) !*Request {
    return Request.init(.{ .url = try exec.call_arena.dupeZ(u8, url) }, null, exec);
}

fn requestUrl(value: js.Value, exec: *const Execution) ![]const u8 {
    if (value.local.jsValueToZig(*Request, value)) |request| {
        return request.getUrl();
    } else |_| {}
    const raw = if (value.isNullOrUndefined()) "" else try value.toZig([]const u8);
    const request = try requestFromUrl(raw, exec);
    return request.getUrl();
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(CacheStorage);

    pub const Meta = struct {
        pub const name = "CacheStorage";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const match = bridge.function(CacheStorage.match, .{});
    pub const has = bridge.function(CacheStorage.has, .{});
    pub const open = bridge.function(CacheStorage.open, .{});
    pub const delete = bridge.function(CacheStorage.delete, .{});
    pub const keys = bridge.function(CacheStorage.keys, .{});
};
