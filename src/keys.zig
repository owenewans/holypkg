const std = @import("std");
const sys = @import("sys.zig");

pub fn add(c: sys.Context, source: []const u8, expected: []const u8, output: []const u8) !void {
    if (expected.len != 40 and expected.len != 64) return error.FullFingerprintRequired;
    for (expected) |ch| if (!std.ascii.isHex(ch)) return error.InvalidFingerprint;
    const work = try c.temp();
    defer std.Io.Dir.cwd().deleteTree(c.io, work) catch {};
    const input = try c.absolute(source);
    const listing = try c.capture(&.{ "gpg", "--homedir", work, "--batch", "--with-colons", "--import-options", "show-only", "--import", "--", input });
    var lines = std.mem.splitScalar(u8, listing, '\n');
    var primary = false;
    var found = false;
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "pub:")) primary = true;
        if (std.mem.startsWith(u8, line, "sub:")) primary = false;
        if (!primary or !std.mem.startsWith(u8, line, "fpr:")) continue;
        var fields = std.mem.splitScalar(u8, line, ':');
        for (0..9) |_| _ = fields.next() orelse return error.InvalidKeyListing;
        const fingerprint = fields.next() orelse return error.InvalidKeyListing;
        if (std.ascii.eqlIgnoreCase(fingerprint, expected)) found = true;
        primary = false;
    }
    if (!found) return error.FingerprintMismatch;
    try c.run(&.{ "gpg", "--homedir", work, "--batch", "--import", "--", input });
    const exported = try c.fmt("{s}/selected.asc", .{work});
    try c.saveOutput(&.{ "gpg", "--homedir", work, "--batch", "--armor", "--export", expected }, exported);
    if ((try c.read(exported)).len == 0) return error.EmptyKeyExport;
    try c.copyNew(exported, output);
    try c.print("Trusted public key {s} written to {s}\nUse --keyring {s}; no global GnuPG trust was changed.\n", .{ expected, output, output });
}
