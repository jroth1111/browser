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
const Execution = js.Execution;
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
//
// Real Chrome's local font inventory is platform-specific: a genuine Windows
// Chrome never has "SF Pro" or "PingFang SC" installed, and a genuine macOS
// Chrome never has "Segoe UI" or "Consolas". Returning a single hardcoded,
// cross-OS font set regardless of the claimed persona is a fingerprinting
// tell (a Win32 persona reporting Mac-only fonts as available, or vice
// versa). The known-family check is gated by the same effective
// `navigator.platform` value Navigator.getPlatform reports (CDP
// Emulation.setUserAgentOverride takes priority over the static persona, so
// this can't silently disagree with what `navigator.platform` returns); when
// no persona profile is loaded (e.g. default/no-authority runs) it falls
// back to the permissive cross-OS set.
pub fn check(_: *const FontFaceSet, font: []const u8, exec: *const Execution) bool {
    return fontHasKnownFamily(font, platformFromExec(exec));
}

fn platformFromExec(exec: *const Execution) ?[]const u8 {
    if (exec.session.browser.http_client.getNavigatorPlatformOverride()) |platform| {
        return platform;
    }
    const authority = exec.session.browser.http_client.network.config.chimeraAuthority() orelse return null;
    return authority.profile.navigator.platform;
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

// Fonts that ship on every desktop Chrome build regardless of host OS
// (generic CSS keywords plus the small set of web-safe/CJK fonts common
// across desktop platforms).
const cross_platform_font_families = [_][]const u8{
    "Arial",            "Arial Black",      "Helvetica",
    "Times",            "Times New Roman",  "Times Roman",
    "Courier",          "Courier New",      "Georgia",
    "Garamond",         "Roboto",           "Open Sans",
    "Source Sans Pro",  "Noto Sans",        "Noto Serif",
    "Noto Mono",        "Noto Sans CJK SC", "Noto Sans CJK JP",
    "Noto Sans CJK KR", "system-ui",        "sans-serif",
    "serif",            "monospace",
};

// Fonts only present on a genuine Windows font inventory.
const windows_font_families = [_][]const u8{
    "Arial Narrow",         "Arial Rounded MT Bold", "Verdana",
    "Tahoma",               "Trebuchet MS",          "Palatino Linotype",
    "Book Antiqua",         "Comic Sans MS",         "Impact",
    "Consolas",             "Segoe UI",              "Calibri",
    "Cambria",              "Corbel",                "Constantia",
    "Microsoft Sans Serif",
};

// Fonts only present on a genuine macOS font inventory.
const macos_font_families = [_][]const u8{
    "Helvetica Neue", "Geneva",              "Lucida Grande",
    "Palatino",       "Didot",               "Bodoni 72",
    "Hoefler Text",   "Iowan Old Style",     "Charter",
    "Optima",         "American Typewriter", "Baskerville",
    "Big Caslon",     "Cochin",              "Snell Roundhand",
    "Copperplate",    "Papyrus",             "Brush Script MT",
    "Marker Felt",    "Chalkduster",         "Chalkboard",
    "Noteworthy",     "Futura",              "Gill Sans",
    "Avenir",         "Avenir Next",         "Menlo",
    "Monaco",         "SF Pro",              "SF Pro Text",
    "SF Pro Display", "SF Mono",             "San Francisco",
    "New York",       "PingFang SC",         "PingFang TC",
    "PingFang HK",    "Hiragino Sans",       "Apple SD Gothic Neo",
    "-apple-system",  "BlinkMacSystemFont",
};

// Fonts only present on a genuine Linux font inventory (the common
// freedesktop/GTK-distro default set).
const linux_font_families = [_][]const u8{
    "Liberation Sans", "Liberation Serif", "Liberation Mono",
    "DejaVu Sans",     "DejaVu Serif",     "DejaVu Sans Mono",
    "Ubuntu",          "Ubuntu Mono",      "Cantarell",
    "Andale Mono",     "Inconsolata",      "Source Code Pro",
    "Fira Code",       "PT Sans",          "PT Serif",
    "PT Mono",
};

fn fontHasKnownFamily(font: []const u8, platform: ?[]const u8) bool {
    const trimmed = std.mem.trim(u8, font, whitespace);
    if (trimmed.len == 0) return false;
    if (std.mem.indexOfScalar(u8, trimmed, ':') != null) return false;

    const family_list = familyListFromFontShorthand(trimmed);
    if (family_list.len == 0) return knownFontFamily(trimmed, platform);
    return familyListHasKnownFamily(family_list, platform);
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

fn familyListHasKnownFamily(input: []const u8, platform: ?[]const u8) bool {
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
            if (familyPartKnown(input[start..idx], platform)) return true;
            start = idx + 1;
        }
    }
    return familyPartKnown(input[start..], platform);
}

fn familyPartKnown(part: []const u8, platform: ?[]const u8) bool {
    var value = std.mem.trim(u8, part, whitespace);
    value = std.mem.trim(u8, value, quote_chars);
    value = std.mem.trim(u8, value, whitespace);
    return knownFontFamily(value, platform);
}

// Platform detection mirrors the `navigator.platform` conventions used
// elsewhere in this codebase (e.g. Navigator.getPlatform, chimera/Profile.zig
// test fixtures): "MacIntel"/"macOS" for macOS, "Win32"/"Windows" for
// Windows, "Linux ..." for Linux. When `platform` is null (no chimera
// persona loaded), every platform's fonts are considered known — matching
// this file's original permissive default and keeping no-persona test runs
// unaffected.
fn knownFontFamily(family: []const u8, platform: ?[]const u8) bool {
    inline for (cross_platform_font_families) |known| {
        if (std.ascii.eqlIgnoreCase(family, known)) return true;
    }

    const plat = platform orelse {
        inline for (windows_font_families) |known| {
            if (std.ascii.eqlIgnoreCase(family, known)) return true;
        }
        inline for (macos_font_families) |known| {
            if (std.ascii.eqlIgnoreCase(family, known)) return true;
        }
        inline for (linux_font_families) |known| {
            if (std.ascii.eqlIgnoreCase(family, known)) return true;
        }
        return false;
    };

    if (isWindowsPlatform(plat)) {
        inline for (windows_font_families) |known| {
            if (std.ascii.eqlIgnoreCase(family, known)) return true;
        }
        return false;
    }
    if (isMacPlatform(plat)) {
        inline for (macos_font_families) |known| {
            if (std.ascii.eqlIgnoreCase(family, known)) return true;
        }
        return false;
    }
    if (isLinuxPlatform(plat)) {
        inline for (linux_font_families) |known| {
            if (std.ascii.eqlIgnoreCase(family, known)) return true;
        }
        return false;
    }

    // Unrecognized platform string: stay conservative rather than silently
    // falling back to the cross-OS-permissive behavior.
    return false;
}

fn isWindowsPlatform(platform: []const u8) bool {
    return containsIgnoreCase(platform, "win");
}

fn isMacPlatform(platform: []const u8) bool {
    return containsIgnoreCase(platform, "mac");
}

fn isLinuxPlatform(platform: []const u8) bool {
    return containsIgnoreCase(platform, "linux") or containsIgnoreCase(platform, "x11");
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
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
    try testing.expect(fontHasKnownFamily("16px sans-serif", null));
    try testing.expect(fontHasKnownFamily("12px Arial", null));
    try testing.expect(fontHasKnownFamily("italic 700 16px/1.5 \"Segoe UI\", sans-serif", null));
    try testing.expect(!fontHasKnownFamily("12px ArialFake", null));
    try testing.expect(!fontHasKnownFamily("italic 16px XX_FAKE_FONT_XX", null));
    try testing.expect(!fontHasKnownFamily("font-family: \"Arial\"", null));
}

// Regression test for R10 finding #17's failure class: a hardcoded,
// non-platform-conditional font inventory that reports a persona's
// off-platform fonts (e.g. Windows-only "Segoe UI" or "Consolas") as
// available even when the claimed `navigator.platform` is macOS, or
// macOS-only fonts ("SF Pro", "PingFang SC", "Menlo") as available on a
// claimed Windows persona. Chrome's real per-OS font inventories never
// overlap like this, so this exact mismatch is a fingerprinting tell.
test "WebApi: FontFaceSet check is gated by claimed platform" {
    // Cross-platform families are always known, regardless of persona.
    try testing.expect(fontHasKnownFamily("16px Arial", "Win32"));
    try testing.expect(fontHasKnownFamily("16px Arial", "MacIntel"));
    try testing.expect(fontHasKnownFamily("16px Arial", "Linux x86_64"));

    // Windows-only fonts must be known on a Windows persona...
    try testing.expect(fontHasKnownFamily("16px Segoe UI", "Win32"));
    try testing.expect(fontHasKnownFamily("16px Consolas", "Windows"));
    // ...and unknown on macOS/Linux personas.
    try testing.expect(!fontHasKnownFamily("16px Segoe UI", "MacIntel"));
    try testing.expect(!fontHasKnownFamily("16px Consolas", "Linux x86_64"));

    // macOS-only fonts must be known on a macOS persona...
    try testing.expect(fontHasKnownFamily("16px SF Pro", "MacIntel"));
    try testing.expect(fontHasKnownFamily("16px Menlo", "macOS"));
    try testing.expect(fontHasKnownFamily("16px PingFang SC", "MacIntel"));
    // ...and unknown on Windows/Linux personas.
    try testing.expect(!fontHasKnownFamily("16px SF Pro", "Win32"));
    try testing.expect(!fontHasKnownFamily("16px Menlo", "Linux x86_64"));

    // Linux-only fonts must be known on a Linux persona...
    try testing.expect(fontHasKnownFamily("16px DejaVu Sans", "Linux x86_64"));
    try testing.expect(fontHasKnownFamily("16px Liberation Sans", "Linux x86_64"));
    // ...and unknown on Windows/macOS personas.
    try testing.expect(!fontHasKnownFamily("16px DejaVu Sans", "Win32"));
    try testing.expect(!fontHasKnownFamily("16px Liberation Sans", "MacIntel"));

    // A font shorthand family list is gated per comma-separated part, same as
    // a bare family: an off-platform first choice with a cross-platform
    // fallback (e.g. "sans-serif") still matches on any platform, since a real
    // browser's `check()` is satisfied if any listed family is available.
    try testing.expect(fontHasKnownFamily("italic 700 16px/1.5 \"Segoe UI\", sans-serif", "MacIntel"));
    try testing.expect(fontHasKnownFamily("italic 700 16px/1.5 \"Segoe UI\", sans-serif", "Win32"));
    // With no cross-platform fallback, an off-platform-only family list is
    // correctly rejected on a mismatched persona.
    try testing.expect(!fontHasKnownFamily("italic 700 16px/1.5 \"Segoe UI\", Consolas", "MacIntel"));
    try testing.expect(fontHasKnownFamily("italic 700 16px/1.5 \"Segoe UI\", Consolas", "Win32"));

    // With no persona loaded (default/no-authority runs), stay permissive
    // across all platforms so existing no-persona behavior is unaffected.
    try testing.expect(fontHasKnownFamily("16px Segoe UI", null));
    try testing.expect(fontHasKnownFamily("16px SF Pro", null));
    try testing.expect(fontHasKnownFamily("16px DejaVu Sans", null));
}

test "WebApi: FontFaceSet" {
    try testing.htmlRunner("css/font_face_set.html", .{});
}
