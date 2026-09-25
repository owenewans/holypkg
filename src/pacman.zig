const std = @import("std");
const sys = @import("sys.zig");
const package = @import("package.zig");
const Context = sys.Context;

pub const Options = struct {
    provider: []const u8,
    name: []const u8,
    repo: ?[]const u8 = null,
    mirror: ?[]const u8 = null,
    testing: bool = false,
    keyring: []const u8,
};

pub const Candidate = struct {
    metadata: package.Metadata,
    filename: []const u8,
    desc: []const u8,
};

pub fn field(desc: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, desc, '\n');
    while (lines.next()) |line| {
        if (line.len >= 2 and line[0] == '%' and line[line.len - 1] == '%' and std.mem.eql(u8, line[1 .. line.len - 1], name)) {
            const start = lines.index orelse return "";
            var end = start;
            while (lines.next()) |value| {
                if (value.len == 0) break;
                end += value.len + 1;
            }
            return std.mem.trimEnd(u8, desc[start..end], "\n");
        }
    }
    return null;
}

pub fn resolve(c: Context, options: Options, work: []const u8) !Candidate {
    if (!sys.safeName(options.name)) return error.InvalidPackageName;
    const artix = std.mem.eql(u8, options.provider, "artix");
    if (!artix and !std.mem.eql(u8, options.provider, "arch")) return error.InvalidProvider;
    const mirror = std.mem.trimEnd(u8, options.mirror orelse if (artix) "https://mirror1.artixlinux.org/repos" else "https://geo.mirror.pkgbuild.com", "/");
    const stable: []const []const u8 = if (artix) &.{ "system", "world", "galaxy", "lib32" } else &.{ "core", "extra", "multilib" };
    const testing: []const []const u8 = if (artix) &.{ "system-gremlins", "world-gremlins", "galaxy-gremlins", "lib32-gremlins" } else &.{ "core-testing", "extra-testing", "multilib-testing" };
    var repos: std.ArrayList([]const u8) = .empty;
    if (options.repo) |repo| {
        if (!sys.safeName(repo)) return error.InvalidRepository;
        if ((std.mem.indexOf(u8, repo, "testing") != null or std.mem.indexOf(u8, repo, "staging") != null or std.mem.indexOf(u8, repo, "gremlins") != null or std.mem.indexOf(u8, repo, "goblins") != null) and !options.testing) return error.TestingRequiresFlag;
        try repos.append(c.a, repo);
    } else {
        try repos.appendSlice(c.a, stable);
        if (options.testing) try repos.appendSlice(c.a, testing);
    }
    var candidates: std.ArrayList(Candidate) = .empty;
    for (repos.items) |repo| {
        const base = try c.fmt("{s}/{s}/os/x86_64", .{ mirror, repo });
        const database = try c.fmt("{s}/{s}.db", .{ work, repo });
        try c.download(try c.fmt("{s}/{s}.db", .{ base, repo }), database);
        const list = try c.capture(&.{ "bsdtar", "-tf", database });
        var names = std.mem.splitScalar(u8, list, '\n');
        const prefix = try c.fmt("{s}-", .{options.name});
        while (names.next()) |path| {
            if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, "/desc")) continue;
            if (!sys.safePath(path)) return error.UnsafeRepositoryPath;
            const desc = try c.capture(&.{ "bsdtar", "-xOf", database, path });
            if (!std.mem.eql(u8, field(desc, "NAME") orelse "", options.name)) continue;
            const filename = field(desc, "FILENAME") orelse return error.MissingPackageFilename;
            if (!sys.safeName(filename)) return error.InvalidPackageFilename;
            const metadata: package.Metadata = .{
                .provider = options.provider,
                .repository = repo,
                .name = options.name,
                .version = field(desc, "VERSION") orelse return error.MissingPackageVersion,
                .architecture = field(desc, "ARCH") orelse return error.MissingArchitecture,
                .source = try c.fmt("{s}/{s}", .{ base, filename }),
                .sha256 = field(desc, "SHA256SUM") orelse return error.MissingChecksum,
                .description = field(desc, "DESC") orelse "foreign binary package",
            };
            try package.validate(metadata);
            if (metadata.sha256.len != 64) return error.InvalidChecksum;
            try candidates.append(c.a, .{ .metadata = metadata, .filename = filename, .desc = desc });
        }
    }
    if (candidates.items.len == 0) return error.PackageNotFound;
    if (candidates.items.len == 1) return candidates.items[0];
    for (candidates.items, 1..) |candidate, i| try c.print("{d}: {s}/{s} {s}\n", .{ i, candidate.metadata.repository, candidate.metadata.name, candidate.metadata.version });
    const chosen = try std.fmt.parseInt(usize, try c.prompt("Repository number: "), 10);
    if (chosen == 0 or chosen > candidates.items.len) return error.InvalidSelection;
    return candidates.items[chosen - 1];
}

pub fn fetch(c: Context, candidate: *Candidate, options: Options, directory: []const u8) ![]const u8 {
    const dest = try c.fmt("{s}/{s}", .{ directory, candidate.filename });
    try c.download(candidate.metadata.source, dest);
    const digest = try c.checksum(dest);
    if (!std.ascii.eqlIgnoreCase(digest, candidate.metadata.sha256)) return error.ChecksumMismatch;
    const sig = try c.fmt("{s}.sig", .{dest});
    try c.download(try c.fmt("{s}.sig", .{candidate.metadata.source}), sig);
    try c.run(&.{ "gpgv", "--keyring", try c.absolute(options.keyring), "--", sig, dest });
    candidate.metadata.signature_verified = true;
    return dest;
}

pub fn deps(c: Context, candidate: Candidate) !void {
    for ([_][]const u8{ "DEPENDS", "OPTDEPENDS", "PROVIDES", "CONFLICTS", "REPLACES" }) |key| {
        try c.print("{s}:\n{s}\n", .{ key, field(candidate.desc, key) orelse "" });
    }
}

test "repository fields preserve lists" {
    const input = "%NAME%\nfoo\n\n%DEPENDS%\nbar>=2\nbaz\n\n%ARCH%\nx86_64\n\n";
    try std.testing.expectEqualStrings("foo", field(input, "NAME").?);
    try std.testing.expectEqualStrings("bar>=2\nbaz", field(input, "DEPENDS").?);
    try std.testing.expect(field(input, "MISSING") == null);
}
