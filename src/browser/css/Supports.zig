const std = @import("std");

const CSSStyleProperties = @import("../webapi/css/CSSStyleProperties.zig");

const ConditionParts = struct {
    left: []const u8,
    right: []const u8,
};

pub fn supports(property_or_condition: []const u8, value: ?[]const u8) bool {
    const subject = trimAscii(property_or_condition);

    if (value) |v| {
        return supportsProperty(subject, trimAscii(v));
    }

    return conditionMatches(subject);
}

pub fn conditionMatches(condition: []const u8) bool {
    const subject = trimAscii(condition);
    if (subject.len == 0) return false;

    if (splitTopLevelKeyword(subject, "or")) |parts| {
        return conditionMatches(parts.left) or conditionMatches(parts.right);
    }

    if (splitTopLevelKeyword(subject, "and")) |parts| {
        return conditionMatches(parts.left) and conditionMatches(parts.right);
    }

    if (consumeLeadingKeyword(subject, "not")) |rest| {
        return !conditionMatches(rest);
    }

    if (selectorFunctionSupported(subject)) return true;

    if (outerParensInner(subject)) |inner| {
        const trimmed = trimAscii(inner);
        if (topLevelColon(trimmed)) |colon| {
            return supportsProperty(trimmed[0..colon], trimmed[colon + 1 ..]);
        }
        return conditionMatches(trimmed);
    }

    return false;
}

fn selectorFunctionSupported(value_: []const u8) bool {
    const value = trimAscii(value_);
    const prefix = "selector(";
    if (value.len < prefix.len + 1) return false;
    if (!startsWithIgnoreCase(value, prefix)) return false;
    if (value[value.len - 1] != ')') return false;

    const selector = trimAscii(value[prefix.len .. value.len - 1]);
    if (selector.len == 0) return false;

    // Narrow Chromium-compatible selector() coverage. This is enough for
    // modern-feature probes such as `CSS.supports("selector(:has(*))")`
    // without pretending to be a full selector parser.
    if (std.ascii.indexOfIgnoreCase(selector, ":has(") != null) return true;
    if (std.mem.indexOfScalar(u8, selector, '*') != null) return true;
    if (std.mem.indexOfScalar(u8, selector, '.') != null) return true;
    if (std.mem.indexOfScalar(u8, selector, '#') != null) return true;
    return isIdentSelector(selector);
}

fn isIdentSelector(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| {
        if (!isIdentChar(ch)) return false;
    }
    return true;
}

fn supportsProperty(property_: []const u8, value_: []const u8) bool {
    const property = trimAscii(property_);
    const value = trimAscii(value_);
    if (property.len == 0 or value.len == 0) return false;

    if (startsWithIgnoreCase(property, "-moz-") or
        startsWithIgnoreCase(property, "-ms-") or
        startsWithIgnoreCase(property, "-o-"))
    {
        return false;
    }

    if (startsWithIgnoreCase(property, "-webkit-")) {
        return webkitSupported(property, value);
    }

    return knownUnprefixedProperty(property) and plausibleValue(value);
}

fn webkitSupported(property: []const u8, value: []const u8) bool {
    if (eqlIgnoreCase(property, "-webkit-appearance")) {
        return oneOfIgnoreCase(value, &.{ "none", "auto", "button", "textfield", "menulist", "searchfield", "checkbox", "radio" });
    }
    if (eqlIgnoreCase(property, "-webkit-transform") or eqlIgnoreCase(property, "-webkit-transition") or
        eqlIgnoreCase(property, "-webkit-animation") or eqlIgnoreCase(property, "-webkit-user-select") or
        eqlIgnoreCase(property, "-webkit-text-size-adjust") or eqlIgnoreCase(property, "-webkit-tap-highlight-color") or
        eqlIgnoreCase(property, "-webkit-backdrop-filter"))
    {
        return plausibleValue(value);
    }

    return false;
}

fn knownUnprefixedProperty(property: []const u8) bool {
    var lower_buf: [128]u8 = undefined;
    if (property.len > lower_buf.len) return false;
    const lower = std.ascii.lowerString(lower_buf[0..property.len], property);
    return CSSStyleProperties.isKnownCSSProperty(lower);
}

fn plausibleValue(value: []const u8) bool {
    return value.len > 0 and
        !eqlIgnoreCase(value, "unsupported") and
        !eqlIgnoreCase(value, "invalid") and
        !std.mem.eql(u8, value, "???");
}

fn trimAscii(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn eqlIgnoreCase(lhs: []const u8, rhs: []const u8) bool {
    return std.ascii.eqlIgnoreCase(lhs, rhs);
}

fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
    return value.len >= prefix.len and std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
}

fn oneOfIgnoreCase(value: []const u8, comptime choices: []const []const u8) bool {
    inline for (choices) |choice| {
        if (eqlIgnoreCase(value, choice)) return true;
    }
    return false;
}

fn consumeLeadingKeyword(value_: []const u8, keyword: []const u8) ?[]const u8 {
    const value = trimAscii(value_);
    if (value.len < keyword.len) return null;
    if (!std.ascii.eqlIgnoreCase(value[0..keyword.len], keyword)) return null;
    if (value.len > keyword.len and isIdentChar(value[keyword.len])) return null;
    return trimAscii(value[keyword.len..]);
}

fn splitTopLevelKeyword(value: []const u8, keyword: []const u8) ?ConditionParts {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < value.len) {
        if (i + 1 < value.len and value[i] == '/' and value[i + 1] == '*') {
            const close = std.mem.indexOfPos(u8, value, i + 2, "*/") orelse return null;
            i = close + 2;
            continue;
        }

        switch (value[i]) {
            '(' => {
                depth += 1;
                i += 1;
                continue;
            },
            ')' => {
                if (depth > 0) depth -= 1;
                i += 1;
                continue;
            },
            else => {},
        }

        if (depth == 0 and isIdentChar(value[i])) {
            const start = i;
            while (i < value.len and isIdentChar(value[i])) : (i += 1) {}
            const word = value[start..i];
            if (std.ascii.eqlIgnoreCase(word, keyword)) {
                const left = trimAscii(value[0..start]);
                const right = trimAscii(value[i..]);
                if (left.len > 0 and right.len > 0) {
                    return .{ .left = left, .right = right };
                }
            }
            continue;
        }

        i += 1;
    }

    return null;
}

fn outerParensInner(value: []const u8) ?[]const u8 {
    if (value.len < 2 or value[0] != '(') return null;

    var depth: usize = 1;
    var i: usize = 1;
    while (i < value.len) {
        if (i + 1 < value.len and value[i] == '/' and value[i + 1] == '*') {
            const close = std.mem.indexOfPos(u8, value, i + 2, "*/") orelse return null;
            i = close + 2;
            continue;
        }
        if (value[i] == '(') {
            depth += 1;
        } else if (value[i] == ')') {
            depth -= 1;
            if (depth == 0) {
                return if (trimAscii(value[i + 1 ..]).len == 0) value[1..i] else null;
            }
        }
        i += 1;
    }
    return null;
}

fn topLevelColon(value: []const u8) ?usize {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < value.len) {
        if (i + 1 < value.len and value[i] == '/' and value[i + 1] == '*') {
            const close = std.mem.indexOfPos(u8, value, i + 2, "*/") orelse return null;
            i = close + 2;
            continue;
        }
        switch (value[i]) {
            '(' => depth += 1,
            ')' => if (depth > 0) {
                depth -= 1;
            },
            ':' => if (depth == 0) return i,
            else => {},
        }
        i += 1;
    }
    return null;
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
}
