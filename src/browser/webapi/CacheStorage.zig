// Copyright (C) 2026 Lightpanda (Selecy SAS)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

const js = @import("../js/js.zig");
const storage = @import("storage/storage.zig");

const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ CacheStorage, Cache };
}

const CacheStorage = @This();

_pad: bool = false,

pub fn match(_: *const CacheStorage, _: js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(js.Undefined{});
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

    pub fn match(_: *const Cache, _: js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        return exec.js.local.?.resolvePromise(js.Undefined{});
    }

    pub fn matchAll(_: *const Cache, _: ?js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        const empty = [_]js.Value{};
        return exec.js.local.?.resolvePromise(empty[0..]);
    }

    pub fn add(_: *const Cache, _: js.Value, exec: *const Execution) !js.Promise {
        return exec.js.local.?.resolvePromise(js.Undefined{});
    }

    pub fn addAll(_: *const Cache, _: []js.Value, exec: *const Execution) !js.Promise {
        return exec.js.local.?.resolvePromise(js.Undefined{});
    }

    pub fn put(_: *const Cache, _: js.Value, _: js.Value, exec: *const Execution) !js.Promise {
        return exec.js.local.?.resolvePromise(js.Undefined{});
    }

    pub fn delete(_: *const Cache, _: js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        return exec.js.local.?.resolvePromise(false);
    }

    pub fn keys(_: *const Cache, _: ?js.Value, _: ?js.Value, exec: *const Execution) !js.Promise {
        const empty = [_]js.Value{};
        return exec.js.local.?.resolvePromise(empty[0..]);
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
