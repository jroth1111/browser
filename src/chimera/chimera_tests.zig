const std = @import("std");

const Authority = @import("Authority.zig");
const Diagnostics = @import("Diagnostics.zig");
const Headers = @import("Headers.zig");
const Profile = @import("Profile.zig");
const Seeds = @import("Seeds.zig");

test {
    std.testing.refAllDecls(Authority);
    std.testing.refAllDecls(Diagnostics);
    std.testing.refAllDecls(Headers);
    std.testing.refAllDecls(Profile);
    std.testing.refAllDecls(Seeds);
}

test "Chimera Diagnostics reports profile-backed canvas active" {
    try Diagnostics.expectProfileBackedCanvasActiveForTest();
}
