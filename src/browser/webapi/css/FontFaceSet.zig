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
const lp = @import("lightpanda");

const js = @import("../../js/js.zig");
const Page = @import("../../Page.zig");
const Frame = @import("../../Frame.zig");

const Event = @import("../Event.zig");
const EventTarget = @import("../EventTarget.zig");

const FontFace = @import("FontFace.zig");

const Allocator = std.mem.Allocator;

const FontFaceSet = @This();

_rc: lp.RC(u8) = .{},
_proto: *EventTarget,
_arena: Allocator,

pub fn init(frame: *Frame) !*FontFaceSet {
    const arena = try frame.getArena(.tiny, "FontFaceSet");
    errdefer frame.releaseArena(arena);

    return frame._factory.eventTargetWithAllocator(arena, FontFaceSet{
        ._proto = undefined,
        ._arena = arena,
    });
}

pub fn deinit(self: *FontFaceSet, page: *Page) void {
    page.releaseArena(self._arena);
}

pub fn releaseRef(self: *FontFaceSet, page: *Page) void {
    self._rc.release(self, page);
}

pub fn acquireRef(self: *FontFaceSet) void {
    self._rc.acquire();
}

pub fn asEventTarget(self: *FontFaceSet) *EventTarget {
    return self._proto;
}

// FontFaceSet.ready - returns an already-resolved Promise.
// In a headless browser there is no font loading, so fonts are always ready.
pub fn getReady(_: *FontFaceSet, frame: *Frame) !js.Promise {
    return frame.js.local.?.resolvePromise({});
}

// check(font, text?) - conservative profile-owned font availability.
pub fn check(_: *const FontFaceSet, font: []const u8) bool {
    return fontHasKnownFamily(font);
}

// load(font, text?) - resolves immediately with an empty array.
pub fn load(self: *FontFaceSet, font: []const u8, frame: *Frame) !js.Promise {
    // TODO parse font to check if the font has been added before dispatching
    // events.
    _ = font;

    // Dispatch loading event
    const target = self.asEventTarget();
    if (frame._event_manager.hasDirectListeners(target, "loading", null)) {
        const event = try Event.initTrusted(comptime .wrap("loading"), .{}, frame._page);
        try frame._event_manager.dispatchDirect(target, event, null, .{ .context = "load font face set" });
    }

    // Dispatch loadingdone event
    if (frame._event_manager.hasDirectListeners(target, "loadingdone", null)) {
        const event = try Event.initTrusted(comptime .wrap("loadingdone"), .{}, frame._page);
        try frame._event_manager.dispatchDirect(target, event, null, .{ .context = "load font face set" });
    }

    return frame.js.local.?.resolvePromise({});
}

// add(fontFace) - no-op; headless browser does not track loaded fonts.
pub fn add(self: *FontFaceSet, _: *FontFace) *FontFaceSet {
    return self;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(FontFaceSet);

    pub const Meta = struct {
        pub const name = "FontFaceSet";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const size = bridge.property(0, .{ .template = false, .readonly = true });
    pub const status = bridge.property("loaded", .{ .template = false, .readonly = true });
    pub const ready = bridge.accessor(FontFaceSet.getReady, null, .{});
    pub const check = bridge.function(FontFaceSet.check, .{});
    pub const load = bridge.function(FontFaceSet.load, .{});
    pub const add = bridge.function(FontFaceSet.add, .{});
};

const testing = @import("../../../testing.zig");

const whitespace = " \t\r\n\x0c";
const quote_chars = "\"'";

const known_font_families = [_][]const u8{
    "Arial",               "Arial Black",       "Arial Narrow",        "Arial Rounded MT Bold",
    "Helvetica",           "Helvetica Neue",    "Times",               "Times New Roman",
    "Times Roman",         "Courier",           "Courier New",         "Courier 10 Pitch",
    "Verdana",             "Tahoma",            "Geneva",              "Lucida",
    "Lucida Sans",         "Lucida Grande",     "Lucida Sans Unicode", "Trebuchet MS",
    "Palatino",            "Palatino Linotype", "Palatino LT STD",     "Book Antiqua",
    "Garamond",            "Georgia",           "Didot",               "Bodoni 72",
    "Hoefler Text",        "Iowan Old Style",   "Charter",             "Optima",
    "American Typewriter", "Baskerville",       "Big Caslon",          "Cochin",
    "Snell Roundhand",     "Copperplate",       "Papyrus",             "Brush Script MT",
    "Brush Script Std",    "Comic Sans MS",     "Comic Sans",          "Impact",
    "Marker Felt",         "Chalkduster",       "Chalkboard",          "Noteworthy",
    "Marker Felt Wide",    "Futura",            "Gill Sans",           "Gill Sans Nova",
    "Avenir",              "Avenir Next",       "Avenir LT STD",       "PT Sans",
    "PT Serif",            "PT Mono",           "Roboto",              "Open Sans",
    "Source Sans Pro",     "Menlo",             "Monaco",              "Andale Mono",
    "Consolas",            "Inconsolata",       "Source Code Pro",     "Fira Code",
    "SF Pro",              "SF Pro Text",       "SF Pro Display",      "SF Mono",
    "San Francisco",       "New York",          "PingFang SC",         "PingFang TC",
    "PingFang HK",         "Hiragino Sans",     "Apple SD Gothic Neo", "Noto Sans",
    "Noto Serif",          "Noto Mono",         "Noto Sans CJK SC",    "Noto Sans CJK JP",
    "Noto Sans CJK KR",    "Liberation Sans",   "Liberation Serif",    "Liberation Mono",
    "DejaVu Sans",         "DejaVu Serif",      "DejaVu Sans Mono",    "DejaVu Sans Condensed",
    "Ubuntu",              "Ubuntu Mono",       "Cantarell",           "Open Sans Condensed",
    "system-ui",           "-apple-system",     "BlinkMacSystemFont",  "sans-serif",
    "serif",               "monospace",
};

fn fontHasKnownFamily(font: []const u8) bool {
    const trimmed = std.mem.trim(u8, font, whitespace);
    if (trimmed.len == 0) return false;
    if (std.mem.indexOfScalar(u8, trimmed, ':') != null) return false;

    const family_list = familyListFromFontShorthand(trimmed);
    if (family_list.len == 0) return knownFontFamily(trimmed);
    return familyListHasKnownFamily(family_list);
}

fn familyListFromFontShorthand(font: []const u8) []const u8 {
    var cursor: usize = 0;
    while (cursor < font.len) {
        while (cursor < font.len and isWhitespace(font[cursor])) cursor += 1;
        const token_start = cursor;
        while (cursor < font.len and !isWhitespace(font[cursor])) cursor += 1;
        if (token_start == cursor) break;
        if (isFontSizeToken(font[token_start..cursor])) {
            return std.mem.trim(u8, font[cursor..], whitespace);
        }
    }
    return "";
}

fn isFontSizeToken(token: []const u8) bool {
    if (token.len == 0) return false;
    const slash_index = std.mem.indexOfScalar(u8, token, '/') orelse token.len;
    const size = token[0..slash_index];
    if (size.len == 0) return false;
    if (std.ascii.isDigit(size[0]) or size[0] == '.') {
        return endsWithIgnoreCase(size, "px") or
            endsWithIgnoreCase(size, "pt") or
            endsWithIgnoreCase(size, "pc") or
            endsWithIgnoreCase(size, "em") or
            endsWithIgnoreCase(size, "rem") or
            endsWithIgnoreCase(size, "ex") or
            endsWithIgnoreCase(size, "ch") or
            endsWithIgnoreCase(size, "cap") or
            endsWithIgnoreCase(size, "ic") or
            endsWithIgnoreCase(size, "lh") or
            endsWithIgnoreCase(size, "rlh") or
            endsWithIgnoreCase(size, "vw") or
            endsWithIgnoreCase(size, "vh") or
            endsWithIgnoreCase(size, "vmin") or
            endsWithIgnoreCase(size, "vmax") or
            endsWithIgnoreCase(size, "vi") or
            endsWithIgnoreCase(size, "vb") or
            endsWithIgnoreCase(size, "cm") or
            endsWithIgnoreCase(size, "mm") or
            endsWithIgnoreCase(size, "q") or
            endsWithIgnoreCase(size, "in") or
            endsWithIgnoreCase(size, "%");
    }
    return std.ascii.eqlIgnoreCase(size, "xx-small") or
        std.ascii.eqlIgnoreCase(size, "x-small") or
        std.ascii.eqlIgnoreCase(size, "small") or
        std.ascii.eqlIgnoreCase(size, "medium") or
        std.ascii.eqlIgnoreCase(size, "large") or
        std.ascii.eqlIgnoreCase(size, "x-large") or
        std.ascii.eqlIgnoreCase(size, "xx-large") or
        std.ascii.eqlIgnoreCase(size, "xxx-large");
}

fn familyListHasKnownFamily(input: []const u8) bool {
    var start: usize = 0;
    var quote: u8 = 0;
    for (input, 0..) |ch, idx| {
        if (quote != 0) {
            if (ch == quote) quote = 0;
            continue;
        }
        if (ch == '"' or ch == '\'') {
            quote = ch;
            continue;
        }
        if (ch == ',') {
            if (familyPartKnown(input[start..idx])) return true;
            start = idx + 1;
        }
    }
    return familyPartKnown(input[start..]);
}

fn familyPartKnown(part: []const u8) bool {
    var value = std.mem.trim(u8, part, whitespace);
    value = std.mem.trim(u8, value, quote_chars);
    value = std.mem.trim(u8, value, whitespace);
    return knownFontFamily(value);
}

fn knownFontFamily(family: []const u8) bool {
    inline for (known_font_families) |known| {
        if (std.ascii.eqlIgnoreCase(family, known)) return true;
    }
    return false;
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or ch == 0x0c;
}

fn endsWithIgnoreCase(value: []const u8, suffix: []const u8) bool {
    if (value.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(value[value.len - suffix.len ..], suffix);
}

test "WebApi: FontFaceSet check rejects unknown-only font families" {
    try testing.expect(fontHasKnownFamily("16px sans-serif"));
    try testing.expect(fontHasKnownFamily("12px Arial"));
    try testing.expect(fontHasKnownFamily("italic 700 16px/1.5 \"Segoe UI\", sans-serif"));
    try testing.expect(!fontHasKnownFamily("12px ArialFake"));
    try testing.expect(!fontHasKnownFamily("italic 16px XX_FAKE_FONT_XX"));
    try testing.expect(!fontHasKnownFamily("font-family: \"Arial\""));
}

test "WebApi: FontFaceSet" {
    try testing.htmlRunner("css/font_face_set.html", .{});
}
