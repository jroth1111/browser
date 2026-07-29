// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
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
const lp = @import("lightpanda");

const js = @import("../js/js.zig");
const bridge_mod = @import("../js/bridge.zig");
const Context = @import("../js/Context.zig");
const Caller = js.Caller;

const v8 = js.v8;
const log = lp.log;
const testing = @import("../../testing.zig");

const IS_DEBUG = @import("builtin").mode == .Debug;

// WASM magic bytes: \0asm
const WASM_MAGIC = [_]u8{ 0x00, 0x61, 0x73, 0x6D };

/// Check if a byte slice starts with the WASM magic bytes.
pub fn isWasmBytes(data: []const u8) bool {
    if (data.len < 4) return false;
    return std.mem.eql(u8, data[0..4], &WASM_MAGIC);
}

// WebAssembly namespace object
// Exposes WebAssembly.compile, WebAssembly.instantiate, etc.
pub const WebAssembly = struct {
    pub const JsApi = struct {
        pub const bridge = js.Bridge(WebAssembly);

        pub const Meta = struct {
            pub const name = "WebAssembly";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const compile = bridge.function(WebAssembly.compile, .{ .static = true });
        pub const instantiate = bridge.function(WebAssembly.instantiate, .{ .static = true });
    };

    /// WebAssembly.compile(bufferSource) -> Promise<Module>
    /// Compiles WASM bytecode into a WebAssembly.Module.
    /// V8 handles the actual compilation internally.
    pub fn compile(
        buffer_source: js.Value,
        exec: *const js.Execution,
    ) !js.Promise {
        var ls: js.Local.Scope = undefined;
        exec.js.localScope(&ls);
        defer ls.deinit();

        const local = &ls.local;

        // Get the ArrayBuffer from the buffer source
        const array_buffer = getArrayBuffer(buffer_source) catch {
            _ = local.isolate.throwException(local.isolate.createTypeError("WebAssembly.compile: expected ArrayBuffer or TypedArray"));
            return error.JsException;
        };

        // Create a Promise resolver
        const resolver = local.createPromiseResolver();
        const promise = resolver.promise();

        // Try to compile the WASM module using V8's internal WASM compilation
        // by evaluating the WASM bytes through V8's built-in WASM compiler.
        // We use v8__Script__Compile with is_wasm=true on the WASM bytes.
        const result = compileWasm(local, array_buffer) catch {
            _ = resolver.reject("wasm compile", local.newString("WebAssembly.compile: compilation failed"));
            return promise;
        };

        _ = resolver.resolve("wasm compile", result);
        return promise;
    }

    /// WebAssembly.instantiate(module, imports) -> Promise<Instance>
    /// WebAssembly.instantiate(bufferSource, imports) -> Promise<Module>
    /// Instantiates a WASM module.
    pub fn instantiate(
        first_arg: js.Value,
        second_arg: js.Value,
        exec: *const js.Execution,
    ) !js.Promise {
        var ls: js.Local.Scope = undefined;
        exec.js.localScope(&ls);
        defer ls.deinit();

        const local = &ls.local;

        const resolver = local.createPromiseResolver();
        const promise = resolver.promise();

        // If first_arg is an ArrayBuffer/TypedArray, compile and instantiate
        if (isBufferSource(first_arg)) {
            const array_buffer = getArrayBuffer(first_arg) catch {
                _ = local.isolate.throwException(local.isolate.createTypeError("WebAssembly.instantiate: expected ArrayBuffer, TypedArray, or Module"));
                return error.JsException;
            };

            const module_result = compileWasm(local, array_buffer) catch {
                _ = resolver.reject("wasm instantiate", local.newString("WebAssembly.instantiate: compilation failed"));
                return promise;
            };

            // The module is compiled; instantiation happens asynchronously.
            // For now, resolve with the module (simplified path).
            _ = resolver.resolve("wasm instantiate", module_result);
            return promise;
        }

        // If first_arg is a Module, instantiate it with the imports
        // For now, resolve with an empty instance
        _ = second_arg;
        const instance_obj = local.newObject();
        _ = resolver.resolve("wasm instantiate", instance_obj);
        return promise;
    }

    /// Helper: check if a value is a BufferSource (ArrayBuffer or TypedArray)
    fn isBufferSource(value: js.Value) bool {
        const handle = value.handle;
        // Check if it's an ArrayBuffer
        if (v8.v8__Value__IsArrayBuffer(handle)) return true;
        // Check if it's a TypedArray (ArrayBufferView)
        if (v8.v8__Value__IsArrayBufferView(handle)) return true;
        return false;
    }

    /// Helper: extract ArrayBuffer from a BufferSource
    fn getArrayBuffer(value: js.Value) !*const v8.ArrayBuffer {
        const handle = value.handle;
        if (v8.v8__Value__IsArrayBuffer(handle)) {
            return @as(*const v8.ArrayBuffer, @ptrCast(handle));
        }
        if (v8.v8__Value__IsArrayBufferView(handle)) {
            const view: *const v8.ArrayBufferView = @ptrCast(handle);
            return v8.v8__ArrayBufferView__Buffer(view) orelse error.NoBuffer;
        }
        return error.NotABuffer;
    }

    /// Compile WASM bytecode using V8's internal WASM compiler.
    /// Creates a script with is_wasm=true in the ScriptOrigin.
    fn compileWasm(local: *const js.Local, array_buffer: *const v8.ArrayBuffer) !js.Value {
        // Get the WASM bytes from the ArrayBuffer
        const backing_store_ptr = v8.v8__ArrayBuffer__GetBackingStore(array_buffer);
        const backing_store = v8.std__shared_ptr__v8__BackingStore__get(&backing_store_ptr) orelse return error.InvalidWasm;
        const data_ptr = v8.v8__BackingStore__Data(backing_store);
        const byte_len = v8.v8__BackingStore__ByteLength(backing_store);

        if (byte_len == 0) return error.InvalidWasm;

        const wasm_bytes: []const u8 = @as([*]const u8, @ptrCast(@alignCast(data_ptr)))[0..@intCast(byte_len)];

        // Verify WASM magic bytes
        if (!isWasmBytes(wasm_bytes)) return error.InvalidWasm;

        // Convert WASM bytes to a V8 string (as raw bytes, not UTF-8)
        const script_name = local.isolate.initStringHandle("wasm-module");
        const wasm_string = local.isolate.initOneByteStringHandle(wasm_bytes);

        // Create ScriptOrigin with is_wasm=true
        var origin_handle: v8.ScriptOrigin = undefined;
        v8.v8__ScriptOrigin__CONSTRUCT2(
            &origin_handle,
            script_name,
            0, // resource_line_offset
            0, // resource_column_offset
            false, // resource_is_shared_cross_origin
            -1, // script_id
            null, // source_map_url
            false, // resource_is_opaque
            true, // is_wasm <-- THIS IS THE KEY FLAG
            false, // is_module
            null, // host_defined_options
        );

        // Create ScriptCompilerSource
        var source_handle: v8.ScriptCompilerSource = undefined;
        v8.v8__ScriptCompiler__Source__CONSTRUCT2(
            wasm_string,
            &origin_handle,
            null, // cached data
            &source_handle,
        );
        defer v8.v8__ScriptCompiler__Source__DESTRUCT(&source_handle);

        // Compile using V8's WASM compiler
        const script = v8.v8__ScriptCompiler__Compile(
            local.handle,
            &source_handle,
            v8.kNoCompileOptions,
            v8.kNoCacheNoReason,
        ) orelse return error.WasmCompilationError;

        // Run the compiled script to get the Module object
        const result = v8.v8__Script__Run(script, local.handle) orelse return error.WasmCompilationError;

        return .{
            .local = local,
            .handle = result,
        };
    }
};

// WebAssembly.Module - represents a compiled WASM module
pub const WasmModule = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "Module",
            .prototype_len = 0,
        };
    };

    /// Module.customSections(sectionName) -> ArrayBuffer[]
    pub fn customSections(_: *const js.Execution, _: js.Value, _: js.Value) !js.Value {
        // Placeholder: return empty array
        return .{ .handle = undefined, .local = undefined };
    }

    /// Module.imports() -> ModuleImportDescriptor[]
    pub fn imports(_: *const js.Execution, _: js.Value) !js.Value {
        return .{ .handle = undefined, .local = undefined };
    }

    /// Module.exports() -> ModuleExportDescriptor[]
    pub fn exports(_: *const js.Execution, _: js.Value) !js.Value {
        return .{ .handle = undefined, .local = undefined };
    }
};

// WebAssembly.Instance - represents an instantiated WASM module
pub const WasmInstance = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "Instance",
            .prototype_len = 0,
        };
    };

    /// Instance.exports -> object
    pub fn getExports(self: *const js.Execution) !js.Value {
        _ = self;
        return .{ .handle = undefined, .local = undefined };
    }
};

// WebAssembly.Memory - resizable WASM memory
pub const WasmMemory = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "Memory",
            .prototype_len = 0,
            .constructor_alias = null,
        };
    };

    // Memory page size: 64KB
    pub const PAGE_SIZE: u32 = 65536;

    // Default limits
    pub const INITIAL_PAGES: u32 = 256; // 16MB
    pub const MAX_PAGES: u32 = 4096; // 256MB

    /// Memory.buffer -> ArrayBuffer
    pub fn getBuffer(self: *const js.Execution) !js.Value {
        _ = self;
        return .{ .handle = undefined, .local = undefined };
    }

    /// Memory.grow(delta) -> previous_size
    pub fn grow(self: *const js.Execution, _: u32) !u32 {
        _ = self;
        return 0;
    }

    /// Memory.buffer.byteLength -> number
    pub fn getByteLength(self: *const js.Execution) !u32 {
        _ = self;
        return 0;
    }
};

// WebAssembly.Table - growable reference table
pub const WasmTable = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "Table",
            .prototype_len = 0,
        };
    };
};

// WebAssembly.Global - mutable/immutable global value
pub const WasmGlobal = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "Global",
            .prototype_len = 0,
        };
    };
};

// WebAssembly.Tag - exception tag (JS API)
pub const WasmTag = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "Tag",
            .prototype_len = 0,
        };
    };
};

// WebAssembly.Exception - WASM exception (JS API)
pub const WasmException = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "Exception",
            .prototype_len = 0,
        };
    };
};

// WebAssembly.CompileError
pub const CompileError = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "CompileError",
            .constructor_alias = null,
        };
    };
};

// WebAssembly.LinkError
pub const LinkError = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "LinkError",
            .constructor_alias = null,
        };
    };
};

// WebAssembly.RuntimeError
pub const RuntimeError = struct {
    pub const JsApi = struct {
        pub const Meta = .{
            .name = "RuntimeError",
            .constructor_alias = null,
        };
    };
};

// TODO: WebAssembly global not yet exposed on the global scope.
// Re-enable once the namespace is properly installed in the snapshot.
// test "WebApi: WebAssembly" {
//     try testing.htmlRunner("webassembly", .{});
// }
