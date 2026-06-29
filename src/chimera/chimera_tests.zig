const std = @import("std");

const Authority = @import("Authority.zig");
const Diagnostics = @import("Diagnostics.zig");
const Headers = @import("Headers.zig");
const Profile = @import("Profile.zig");
const Seeds = @import("Seeds.zig");
const CdpIdentity = @import("CdpIdentity.zig");

test {
    std.testing.refAllDecls(Authority);
    std.testing.refAllDecls(Diagnostics);
    std.testing.refAllDecls(Headers);
    std.testing.refAllDecls(Profile);
    std.testing.refAllDecls(Seeds);
    std.testing.refAllDecls(CdpIdentity);
}

test "Chimera Diagnostics reports profile evidence tiers" {
    try Diagnostics.expectProfileEvidenceTiersForTest();
}
