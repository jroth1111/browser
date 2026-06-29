// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
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

const js = @import("../js/js.zig");
const Execution = js.Execution;
const ChimeraProfile = @import("../../chimera/Profile.zig");

pub fn registerTypes() []const type {
    return &.{ PluginArray, Plugin, MimeTypeArray, MimeType };
}

const PluginArray = @This();

_pad: bool = false,

pub fn refresh(_: *const PluginArray) void {}
pub fn getLength(_: *const PluginArray, exec: *const Execution) u32 {
    return if (pdfEnabled(exec)) pdf_plugins.len else 0;
}

pub fn getAtIndex(_: *const PluginArray, index: u32, exec: *const Execution) ?*Plugin {
    if (pdfEnabled(exec) and index < pdf_plugins.len) return &pdf_plugins[index];
    return null;
}

pub fn getByName(_: *const PluginArray, name: []const u8, exec: *const Execution) ?*Plugin {
    if (!pdfEnabled(exec)) return null;
    for (&pdf_plugins) |*plugin| {
        if (pluginNameMatches(plugin, name)) {
            return plugin;
        }
    }
    return null;
}

pub const MimeTypeArray = struct {
    _pad: bool = false,

    pub fn getLength(_: *const MimeTypeArray, exec: *const Execution) u32 {
        return if (pdfEnabled(exec)) pdf_mime_types.len else 0;
    }

    pub fn getAtIndex(_: *const MimeTypeArray, index: u32, exec: *const Execution) ?*MimeType {
        if (pdfEnabled(exec) and index < pdf_mime_types.len) return &pdf_mime_types[index];
        return null;
    }

    pub fn getByName(_: *const MimeTypeArray, name: []const u8, exec: *const Execution) ?*MimeType {
        if (!pdfEnabled(exec)) return null;
        for (&pdf_mime_types) |*mime_type| {
            if (std.mem.eql(u8, name, mime_type.type_name)) {
                return mime_type;
            }
        }
        return null;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeTypeArray);

        pub const Meta = struct {
            pub const name = "MimeTypeArray";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const length = bridge.accessor(MimeTypeArray.getLength, null, .{});
        pub const @"[int]" = bridge.indexed(MimeTypeArray.getAtIndex, null, .{ .null_as_undefined = true });
        pub const @"[str]" = bridge.namedIndexed(MimeTypeArray.getByName, null, null, .{ .null_as_undefined = true });
        pub const item = bridge.function(_item, .{});
        fn _item(self: *const MimeTypeArray, index: i32, exec: *const Execution) ?*MimeType {
            if (index < 0) {
                return null;
            }
            return self.getAtIndex(@intCast(index), exec);
        }
        pub const namedItem = bridge.function(MimeTypeArray.getByName, .{});
    };
};

pub const Plugin = struct {
    _pad: bool = false,
    name: []const u8 = "",
    filename: []const u8 = "internal-pdf-viewer",
    description: []const u8 = pdf_plugin_description,

    pub fn getName(self: *const Plugin) []const u8 {
        return self.name;
    }

    pub fn getFilename(self: *const Plugin) []const u8 {
        return self.filename;
    }

    pub fn getDescription(self: *const Plugin) []const u8 {
        return self.description;
    }

    pub fn getLength(_: *const Plugin, exec: *const Execution) u32 {
        return if (pdfEnabled(exec)) pdf_mime_types.len else 0;
    }

    pub fn getAtIndex(_: *const Plugin, index: u32, exec: *const Execution) ?*MimeType {
        if (pdfEnabled(exec) and index < pdf_mime_types.len) return &pdf_mime_types[index];
        return null;
    }

    pub fn getByName(_: *const Plugin, name: []const u8, exec: *const Execution) ?*MimeType {
        if (!pdfEnabled(exec)) return null;
        for (&pdf_mime_types) |*mime_type| {
            if (std.mem.eql(u8, name, mime_type.type_name)) {
                return mime_type;
            }
        }
        return null;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Plugin);
        pub const Meta = struct {
            pub const name = "Plugin";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const name = bridge.accessor(Plugin.getName, null, .{});
        pub const filename = bridge.accessor(Plugin.getFilename, null, .{});
        pub const description = bridge.accessor(Plugin.getDescription, null, .{});
        pub const length = bridge.accessor(Plugin.getLength, null, .{});
        pub const @"[int]" = bridge.indexed(Plugin.getAtIndex, null, .{ .null_as_undefined = true });
        pub const @"[str]" = bridge.namedIndexed(Plugin.getByName, null, null, .{ .null_as_undefined = true });
        pub const item = bridge.function(_item, .{});
        fn _item(self: *const Plugin, index: i32, exec: *const Execution) ?*MimeType {
            if (index < 0) {
                return null;
            }
            return self.getAtIndex(@intCast(index), exec);
        }
        pub const namedItem = bridge.function(Plugin.getByName, .{});
    };
};

pub const MimeType = struct {
    _pad: bool = false,
    type_name: []const u8 = "",
    suffixes: []const u8 = "pdf",
    description: []const u8 = pdf_plugin_description,

    pub fn getType(self: *const MimeType) []const u8 {
        return self.type_name;
    }

    pub fn getSuffixes(self: *const MimeType) []const u8 {
        return self.suffixes;
    }

    pub fn getDescription(self: *const MimeType) []const u8 {
        return self.description;
    }

    pub fn getEnabledPlugin(_: *const MimeType, exec: *const Execution) ?*Plugin {
        return if (pdfEnabled(exec)) &pdf_plugins[0] else null;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeType);
        pub const Meta = struct {
            pub const name = "MimeType";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const @"type" = bridge.accessor(MimeType.getType, null, .{});
        pub const suffixes = bridge.accessor(MimeType.getSuffixes, null, .{});
        pub const description = bridge.accessor(MimeType.getDescription, null, .{});
        pub const enabledPlugin = bridge.accessor(MimeType.getEnabledPlugin, null, .{ .null_as_undefined = true });
    };
};

const pdf_plugin_filename = "internal-pdf-viewer";
const pdf_plugin_description = "Portable Document Format";

var pdf_plugins = [_]Plugin{
    .{ .name = "PDF Viewer", .filename = pdf_plugin_filename, .description = pdf_plugin_description },
    .{ .name = "Chrome PDF Viewer", .filename = pdf_plugin_filename, .description = pdf_plugin_description },
    .{ .name = "Chromium PDF Viewer", .filename = pdf_plugin_filename, .description = pdf_plugin_description },
    .{ .name = "Microsoft Edge PDF Viewer", .filename = pdf_plugin_filename, .description = pdf_plugin_description },
    .{ .name = "WebKit built-in PDF", .filename = pdf_plugin_filename, .description = pdf_plugin_description },
};

var pdf_mime_types = [_]MimeType{
    .{ .type_name = "application/pdf", .suffixes = "pdf", .description = pdf_plugin_description },
    .{ .type_name = "text/pdf", .suffixes = "pdf", .description = pdf_plugin_description },
};

fn pluginNameMatches(plugin: *const Plugin, name: []const u8) bool {
    return std.mem.eql(u8, name, plugin.name);
}

fn chimeraProfile(exec: *const Execution) ?*const ChimeraProfile {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return null;
    return &authority.profile;
}

fn pdfEnabled(exec: *const Execution) bool {
    const profile = chimeraProfile(exec) orelse return false;
    return profile.plugins.pdf_enabled;
}

test "WebApi: PluginArray named lookup does not match internal PDF filename" {
    try std.testing.expect(pluginNameMatches(&pdf_plugins[0], "PDF Viewer"));
    try std.testing.expect(!pluginNameMatches(&pdf_plugins[0], pdf_plugin_filename));
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(PluginArray);

    pub const Meta = struct {
        pub const name = "PluginArray";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const length = bridge.accessor(PluginArray.getLength, null, .{});
    pub const refresh = bridge.function(PluginArray.refresh, .{});
    pub const @"[int]" = bridge.indexed(PluginArray.getAtIndex, null, .{ .null_as_undefined = true });
    pub const @"[str]" = bridge.namedIndexed(PluginArray.getByName, null, null, .{ .null_as_undefined = true });
    pub const item = bridge.function(_item, .{});
    fn _item(self: *const PluginArray, index: i32, exec: *const Execution) ?*Plugin {
        if (index < 0) {
            return null;
        }
        return self.getAtIndex(@intCast(index), exec);
    }
    pub const namedItem = bridge.function(PluginArray.getByName, .{});
};
