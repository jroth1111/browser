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
    return if (pdfEnabled(exec)) 1 else 0;
}

pub fn getAtIndex(_: *const PluginArray, index: u32, exec: *const Execution) ?*Plugin {
    if (index == 0 and pdfEnabled(exec)) return &pdf_plugin;
    return null;
}

pub fn getByName(_: *const PluginArray, name: []const u8, exec: *const Execution) ?*Plugin {
    if (pdfEnabled(exec) and matchesAny(name, &.{ pdf_plugin_name, pdf_plugin_filename })) {
        return &pdf_plugin;
    }
    return null;
}

pub const MimeTypeArray = struct {
    _pad: bool = false,

    pub fn getLength(_: *const MimeTypeArray, exec: *const Execution) u32 {
        return if (pdfEnabled(exec)) 1 else 0;
    }

    pub fn getAtIndex(_: *const MimeTypeArray, index: u32, exec: *const Execution) ?*MimeType {
        if (index == 0 and pdfEnabled(exec)) return &pdf_mime_type;
        return null;
    }

    pub fn getByName(_: *const MimeTypeArray, name: []const u8, exec: *const Execution) ?*MimeType {
        if (pdfEnabled(exec) and matchesAny(name, &.{pdf_mime_type_name})) {
            return &pdf_mime_type;
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

    pub fn getName(_: *const Plugin) []const u8 {
        return pdf_plugin_name;
    }

    pub fn getFilename(_: *const Plugin) []const u8 {
        return pdf_plugin_filename;
    }

    pub fn getDescription(_: *const Plugin) []const u8 {
        return pdf_plugin_description;
    }

    pub fn getLength(_: *const Plugin, exec: *const Execution) u32 {
        return if (pdfEnabled(exec)) 1 else 0;
    }

    pub fn getAtIndex(_: *const Plugin, index: u32, exec: *const Execution) ?*MimeType {
        if (index == 0 and pdfEnabled(exec)) return &pdf_mime_type;
        return null;
    }

    pub fn getByName(_: *const Plugin, name: []const u8, exec: *const Execution) ?*MimeType {
        if (pdfEnabled(exec) and matchesAny(name, &.{pdf_mime_type_name})) {
            return &pdf_mime_type;
        }
        return null;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Plugin);
        pub const Meta = struct {
            pub const name = "Plugin";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
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

    pub fn getType(_: *const MimeType) []const u8 {
        return pdf_mime_type_name;
    }

    pub fn getSuffixes(_: *const MimeType) []const u8 {
        return "pdf";
    }

    pub fn getDescription(_: *const MimeType) []const u8 {
        return pdf_plugin_description;
    }

    pub fn getEnabledPlugin(_: *const MimeType, exec: *const Execution) ?*Plugin {
        return if (pdfEnabled(exec)) &pdf_plugin else null;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeType);
        pub const Meta = struct {
            pub const name = "MimeType";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const @"type" = bridge.accessor(MimeType.getType, null, .{});
        pub const suffixes = bridge.accessor(MimeType.getSuffixes, null, .{});
        pub const description = bridge.accessor(MimeType.getDescription, null, .{});
        pub const enabledPlugin = bridge.accessor(MimeType.getEnabledPlugin, null, .{ .null_as_undefined = true });
    };
};

const pdf_plugin_name = "PDF Viewer";
const pdf_plugin_filename = "internal-pdf-viewer";
const pdf_plugin_description = "Portable Document Format";
const pdf_mime_type_name = "application/pdf";

var pdf_plugin: Plugin = .{};
var pdf_mime_type: MimeType = .{};

fn chimeraProfile(exec: *const Execution) ?*const ChimeraProfile {
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return null;
    return &authority.profile;
}

fn pdfEnabled(exec: *const Execution) bool {
    const profile = chimeraProfile(exec) orelse return false;
    return profile.plugins.pdf_enabled;
}

fn matchesAny(value: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.eql(u8, value, needle)) {
            return true;
        }
    }
    return false;
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
