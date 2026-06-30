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

const js = @import("../js/js.zig");

const Navigator = @import("Navigator.zig");
const Permissions = @import("Permissions.zig");
const StorageManager = @import("StorageManager.zig");
const NavigatorUAData = @import("NavigatorUAData.zig");

const Execution = js.Execution;
const WorkerNavigator = @This();

_navigator: Navigator = .init,

pub const init: WorkerNavigator = .{};

pub fn getUserAgent(self: *const WorkerNavigator, exec: *const Execution) []const u8 {
    return self._navigator.getUserAgent(exec);
}

pub fn getLanguages(self: *const WorkerNavigator, exec: *const Execution) []const []const u8 {
    return self._navigator.getLanguages(exec);
}

pub fn getDoNotTrack(self: *const WorkerNavigator) ?[]const u8 {
    return self._navigator.getDoNotTrack();
}

pub fn getAppName(self: *const WorkerNavigator) []const u8 {
    return self._navigator.getAppName();
}

pub fn getAppCodeName(self: *const WorkerNavigator) []const u8 {
    return self._navigator.getAppCodeName();
}

pub fn getAppVersion(self: *const WorkerNavigator, exec: *const Execution) []const u8 {
    return self._navigator.getAppVersion(exec);
}

pub fn getLanguage(self: *const WorkerNavigator, exec: *const Execution) []const u8 {
    return self._navigator.getLanguage(exec);
}

pub fn getOnLine(self: *const WorkerNavigator) bool {
    return self._navigator.getOnLine();
}

pub fn getCookieEnabled(self: *const WorkerNavigator) bool {
    return self._navigator.getCookieEnabled();
}

pub fn getHardwareConcurrency(self: *const WorkerNavigator, exec: *const Execution) u32 {
    return self._navigator.getHardwareConcurrency(exec);
}

pub fn getDeviceMemory(self: *const WorkerNavigator, exec: *const Execution) f64 {
    return self._navigator.getDeviceMemory(exec);
}

pub fn getMaxTouchPoints(self: *const WorkerNavigator, exec: *const Execution) u32 {
    return self._navigator.getMaxTouchPoints(exec);
}

pub fn getVendor(self: *const WorkerNavigator, exec: *const Execution) []const u8 {
    return self._navigator.getVendor(exec);
}

pub fn getProduct(self: *const WorkerNavigator, exec: *const Execution) []const u8 {
    return self._navigator.getProduct(exec);
}

pub fn getWebdriver(self: *const WorkerNavigator, exec: *const Execution) bool {
    return self._navigator.getWebdriver(exec);
}

pub fn getGlobalPrivacyControl(self: *const WorkerNavigator) bool {
    return self._navigator.getGlobalPrivacyControl();
}

pub fn getPlatform(self: *const WorkerNavigator, exec: *const Execution) []const u8 {
    return self._navigator.getPlatform(exec);
}

pub fn javaEnabled(self: *const WorkerNavigator) bool {
    return self._navigator.javaEnabled();
}

pub fn getPermissions(self: *WorkerNavigator) *Permissions {
    return self._navigator.getPermissions();
}

pub fn getStorage(self: *WorkerNavigator) *StorageManager {
    return self._navigator.getStorage();
}

pub fn getUserAgentData(self: *WorkerNavigator) *NavigatorUAData {
    return self._navigator.getUserAgentData();
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(WorkerNavigator);

    pub const Meta = struct {
        pub const name = "WorkerNavigator";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const userAgent = bridge.accessor(WorkerNavigator.getUserAgent, null, .{});
    pub const appName = bridge.accessor(WorkerNavigator.getAppName, null, .{});
    pub const appCodeName = bridge.accessor(WorkerNavigator.getAppCodeName, null, .{});
    pub const appVersion = bridge.accessor(WorkerNavigator.getAppVersion, null, .{});
    pub const platform = bridge.accessor(WorkerNavigator.getPlatform, null, .{});
    pub const language = bridge.accessor(WorkerNavigator.getLanguage, null, .{});
    pub const languages = bridge.accessor(WorkerNavigator.getLanguages, null, .{});
    pub const onLine = bridge.accessor(WorkerNavigator.getOnLine, null, .{});
    pub const cookieEnabled = bridge.accessor(WorkerNavigator.getCookieEnabled, null, .{});
    pub const hardwareConcurrency = bridge.accessor(WorkerNavigator.getHardwareConcurrency, null, .{});
    pub const deviceMemory = bridge.accessor(WorkerNavigator.getDeviceMemory, null, .{});
    pub const maxTouchPoints = bridge.accessor(WorkerNavigator.getMaxTouchPoints, null, .{});
    pub const vendor = bridge.accessor(WorkerNavigator.getVendor, null, .{});
    pub const product = bridge.accessor(WorkerNavigator.getProduct, null, .{});
    pub const webdriver = bridge.accessor(WorkerNavigator.getWebdriver, null, .{});
    pub const doNotTrack = bridge.accessor(WorkerNavigator.getDoNotTrack, null, .{});
    pub const globalPrivacyControl = bridge.accessor(WorkerNavigator.getGlobalPrivacyControl, null, .{});

    pub const javaEnabled = bridge.function(WorkerNavigator.javaEnabled, .{});
    pub const permissions = bridge.accessor(WorkerNavigator.getPermissions, null, .{});
    pub const storage = bridge.accessor(WorkerNavigator.getStorage, null, .{});
    pub const userAgentData = bridge.accessor(WorkerNavigator.getUserAgentData, null, .{});
};
