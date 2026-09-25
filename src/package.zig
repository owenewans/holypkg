const std = @import("std");
const sys = @import("sys.zig");
const archive = @import("archive.zig");
const Context = sys.Context;

pub const Metadata = struct {
    schema: u32 = 1,
    provider: []const u8,
    repository: []const u8 = "local",
    name: []const u8,
    version: []const u8,
    architecture: []const u8,
    source: []const u8,
    sha256: []const u8,
    source_checksum: []const u8 = "",
    source_checksum_algorithm: []const u8 = "sha256",
    signature_verified: bool = false,
    ownership: []const u8 = "source-root",
    description: []const u8 = "foreign binary package",
};

pub fn value(data: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const eq = std.mem.indexOf(u8, line, " = ") orelse continue;
        if (std.mem.eql(u8, line[0..eq], key)) return line[eq + 3 ..];
    }
    return null;
}

pub fn parsePacman(data: []const u8, provider: []const u8, source: []const u8, digest: []const u8) !Metadata {
    if (!std.mem.eql(u8, provider, "arch") and !std.mem.eql(u8, provider, "artix")) return error.PacmanProviderRequired;
    const result: Metadata = .{
        .provider = provider,
        .name = value(data, "pkgname") orelse return error.MissingPackageName,
        .version = value(data, "pkgver") orelse return error.MissingPackageVersion,
        .architecture = value(data, "arch") orelse return error.MissingArchitecture,
        .description = value(data, "pkgdesc") orelse "foreign binary package",
        .source = source,
        .sha256 = digest,
    };
    try validate(result);
    return result;
}

pub fn validate(m: Metadata) !void {
    if (!sys.safeName(m.name)) return error.InvalidPackageName;
    if (m.version.len == 0) return error.InvalidVersion;
    for (m.version) |ch| if (!std.ascii.isAlphanumeric(ch) and std.mem.indexOfScalar(u8, ".+-_:~", ch) == null) return error.InvalidVersion;
    for (m.description) |ch| if (ch < 32 or ch == 127) return error.InvalidDescription;
    if (!std.mem.eql(u8, m.architecture, "x86_64") and !std.mem.eql(u8, m.architecture, "any") and !std.mem.eql(u8, m.architecture, "noarch") and !std.mem.eql(u8, m.architecture, "amd64") and !std.mem.eql(u8, m.architecture, "all")) return error.UnsupportedArchitecture;
    const providers = [_][]const u8{ "arch", "artix", "debian", "ubuntu", "fedora", "opensuse", "github", "url" };
    for (providers) |provider| if (std.mem.eql(u8, m.provider, provider)) return;
    return error.InvalidProvider;
}

pub fn filename(c: Context, m: Metadata) ![]const u8 {
    try validate(m);
    var encoded: std.Io.Writer.Allocating = .init(c.a);
    for (m.version) |ch| {
        if (ch == '-' or ch == ':' or ch == '~' or ch == '+') {
            try encoded.writer.print("+{x:0>2}", .{ch});
        } else try encoded.writer.writeByte(ch);
    }
    const version = encoded.written();
    const arch = if (std.mem.eql(u8, m.architecture, "any") or std.mem.eql(u8, m.architecture, "all") or std.mem.eql(u8, m.architecture, "noarch")) "noarch" else "x86_64";
    const tag = if (std.mem.eql(u8, m.provider, "github")) "gh" else m.provider;
    return c.fmt("{s}-{s}-{s}-1_holy{s}.txz", .{ m.name, version, arch, tag });
}

pub fn readStage(c: Context, stage: []const u8) !Metadata {
    const data = try c.read(try c.fmt("{s}/package.json", .{stage}));
    const parsed = try std.json.parseFromSlice(Metadata, c.a, data, .{ .allocate = .alloc_always });
    try validate(parsed.value);
    return parsed.value;
}

pub fn finishStage(c: Context, stage: []const u8, m: Metadata, entries: []archive.Entry) !void {
    try validate(m);
    const doc = try c.fmt("usr/doc/{s}/holypkg", .{m.name});
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.path, doc) or std.mem.startsWith(u8, entry.path, try c.fmt("{s}/", .{doc}))) return error.ProvenanceCollision;
        var parent: ?[]const u8 = doc;
        while (parent) |p| {
            if (std.mem.eql(u8, entry.path, p) and entry.kind != '5') return error.ProvenancePathThroughLink;
            parent = std.fs.path.dirname(p);
        }
    }
    const root = try c.fmt("{s}/root", .{stage});
    const json = try std.json.Stringify.valueAlloc(c.a, m, .{ .whitespace = .indent_2 });
    try c.write(try c.fmt("{s}/package.json", .{stage}), json);
    try c.write(try c.fmt("{s}/{s}/provenance.json", .{ root, doc }), json);
    try c.write(try c.fmt("{s}/{s}/source-files.json", .{ root, doc }), try std.json.Stringify.valueAlloc(c.a, entries, .{ .whitespace = .indent_2 }));
    const reserved = [_][]const u8{ ".PKGINFO", ".BUILDINFO", ".MTREE", ".INSTALL", ".CHANGELOG", "install" };
    var payload: std.Io.Writer.Allocating = .init(c.a);
    for (entries) |entry| {
        var metadata = false;
        for (reserved) |name| {
            if (std.mem.eql(u8, entry.path, name) or (std.mem.eql(u8, name, "install") and std.mem.startsWith(u8, entry.path, "install/"))) metadata = true;
        }
        if (!metadata) try payload.writer.print("{s}\n", .{entry.path});
    }
    try c.write(try c.fmt("{s}/payload.list", .{stage}), payload.written());
    for (reserved) |name| {
        var exists = false;
        for (entries) |entry| if (std.mem.eql(u8, entry.path, name) or (std.mem.eql(u8, name, "install") and std.mem.startsWith(u8, entry.path, "install/"))) {
            exists = true;
            break;
        };
        if (exists) {
            const src = try c.fmt("{s}/{s}", .{ root, name });
            const dest = try c.fmt("{s}/{s}/original/{s}", .{ root, doc, name });
            try std.Io.Dir.cwd().createDirPath(c.io, std.fs.path.dirname(dest).?);
            try c.run(&.{ "mv", "--", src, dest });
        }
    }
    var desc: std.Io.Writer.Allocating = .init(c.a);
    try desc.writer.print("{s}: {s} ({s})\n{s}:\n{s}: Imported from {s}; dependencies are not installed.\n", .{ m.name, m.name, m.description, m.name, m.name, m.provider });
    for (0..8) |_| try desc.writer.print("{s}:\n", .{m.name});
    try c.write(try c.fmt("{s}/install/slack-desc", .{root}), desc.written());
    try c.print("stage: {s}\npackage: {s}\n", .{ stage, try filename(c, m) });
}

pub fn stagePacman(c: Context, input: []const u8, provider: []const u8, stage: []const u8, options: archive.ExtractOptions, provenance: ?Metadata) !void {
    const work = try c.temp();
    defer std.Io.Dir.cwd().deleteTree(c.io, work) catch {};
    // mkdir fails if the stage already exists; never overlay a previous tree.
    try std.Io.Dir.cwd().createDir(c.io, stage, .default_dir);
    const a = try archive.normalize(c, input, work);
    var metadata_found = false;
    for (a.entries) |entry| {
        if (std.mem.eql(u8, entry.path, ".PKGINFO")) {
            if (entry.kind != '0') return error.InvalidMetadataType;
            metadata_found = true;
        }
    }
    if (!metadata_found) return error.MissingPackageMetadata;
    try archive.extract(c, a, try c.fmt("{s}/root", .{stage}), options);
    const metadata = try c.read(try c.fmt("{s}/root/.PKGINFO", .{stage}));
    var m = try parsePacman(metadata, provider, try c.absolute(input), try c.checksum(input));
    m.ownership = if (options.root_owner) "root" else "source-root";
    if (provenance) |p| {
        if (!std.mem.eql(u8, p.name, m.name) or !std.mem.eql(u8, p.version, m.version) or !std.mem.eql(u8, p.sha256, m.sha256)) return error.RepositoryMetadataMismatch;
        m.repository = p.repository;
        m.source = p.source;
        m.signature_verified = p.signature_verified;
    }
    try finishStage(c, stage, m, a.entries);
}

pub fn pack(c: Context, stage: []const u8, output: []const u8) ![]const u8 {
    const m = try readStage(c, stage);
    const root = try c.absolute(try c.fmt("{s}/root", .{stage}));
    try std.Io.Dir.cwd().createDirPath(c.io, output);
    const dest = try c.fmt("{s}/{s}", .{ try c.absolute(output), try filename(c, m) });
    const existing = std.Io.Dir.cwd().openFile(c.io, dest, .{}) catch null;
    if (existing) |f| {
        f.close(c.io);
        return error.OutputAlreadyExists;
    }
    try c.print("packing {s}\n", .{dest});
    const script = std.Io.Dir.cwd().openFile(c.io, try c.fmt("{s}/install/doinst.sh", .{root}), .{}) catch null;
    if (script) |f| {
        f.close(c.io);
        try c.print("install/doinst.sh is present; pkgtools will execute it during installation.\n", .{});
    }
    // Payload ownership is root:root (foreign ownership requires manual handling).
    // Set tar header ownership without changing staging modes or requiring root.
    const command: []const []const u8 = &.{ "env", "TAR_OPTIONS=--owner=0 --group=0 --numeric-owner", "makepkg", "-l", "n", "-c", "n", dest };
    var child = try std.process.spawn(c.io, .{
        .argv = command,
        .cwd = .{ .path = root },
    });
    const term = try child.wait(c.io);
    if (term != .exited or term.exited != 0) return error.MakepkgFailed;
    return dest;
}

test "pacman metadata is exact and does not interpret shell" {
    const m = try parsePacman("pkgname = foo\npkgver = 1:2.3-4\narch = x86_64\ndepend = bar\n", "artix", "local", "hash");
    try std.testing.expectEqualStrings("1:2.3-4", m.version);
    try std.testing.expectError(error.PacmanProviderRequired, parsePacman("", "url", "", ""));
    try std.testing.expectError(error.InvalidPackageName, parsePacman("pkgname = $(id)\npkgver = 1\narch = any\n", "arch", "", ""));
}
