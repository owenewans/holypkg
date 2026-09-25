const std = @import("std");
const sys = @import("sys.zig");
const package = @import("package.zig");
const foreign = @import("foreign.zig");
const Context = sys.Context;

pub const Options = struct {
    provider: []const u8,
    name: []const u8,
    mirror: ?[]const u8 = null,
    repo: ?[]const u8 = null,
    suite: ?[]const u8 = null,
    keyring: []const u8,
};
pub const Candidate = struct {
    metadata: package.Metadata,
    filename: []const u8,
    original: []const u8,
};

fn verifyHash(c: Context, path: []const u8, expected: []const u8) !void {
    const actual = switch (expected.len) {
        64 => try c.checksum(path),
        128 => (try c.capture(&.{ "sha512sum", "--", path }))[0..128],
        else => return error.UnsupportedChecksum,
    };
    if (!std.ascii.eqlIgnoreCase(expected, actual)) return error.ChecksumMismatch;
}

pub fn unpackIndex(c: Context, input: []const u8, destination: []const u8, name: []const u8) ![]const u8 {
    const command = if (std.mem.endsWith(u8, name, ".xz")) "xz" else if (std.mem.endsWith(u8, name, ".gz")) "gzip" else if (std.mem.endsWith(u8, name, ".zst")) "zstd" else if (std.mem.endsWith(u8, name, ".bz2")) "bzip2" else return error.UnsupportedIndexCompression;
    try c.saveOutput(&.{ command, "-dc", "--", input }, destination);
    return std.Io.Dir.cwd().readFileAlloc(c.io, destination, c.a, .limited(512 * 1024 * 1024));
}

pub fn deb(c: Context, o: Options, work: []const u8) !Candidate {
    const ubuntu = std.mem.eql(u8, o.provider, "ubuntu");
    const mirror = std.mem.trimEnd(u8, o.mirror orelse if (ubuntu) "https://archive.ubuntu.com/ubuntu" else "https://deb.debian.org/debian", "/");
    const suite = o.suite orelse if (ubuntu) "devel" else "sid";
    const component = o.repo orelse "main";
    if (!sys.safeName(suite) or !sys.safeName(component) or !sys.safeName(o.name)) return error.InvalidRepository;
    const base = try c.fmt("{s}/dists/{s}", .{ mirror, suite });
    const signed = try c.fmt("{s}/InRelease", .{work});
    const release = try c.fmt("{s}/Release", .{work});
    try c.download(try c.fmt("{s}/InRelease", .{base}), signed);
    try c.run(&.{ "gpgv", "--keyring", try c.verificationKey(o.keyring, work), "--output", release, "--", signed });
    const data = try c.read(release);
    const index_name = try c.fmt("{s}/binary-amd64/Packages.xz", .{component});
    var lines = std.mem.splitScalar(u8, data, '\n');
    var in_sha256 = false;
    var hash: ?[]const u8 = null;
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "SHA256:") or std.mem.eql(u8, line, "SHA512:")) {
            in_sha256 = true;
            continue;
        }
        if (line.len > 0 and line[0] != ' ') in_sha256 = false;
        if (!in_sha256) continue;
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const digest = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const path = fields.next() orelse continue;
        if (std.mem.eql(u8, path, index_name) and (hash == null or digest.len == 64)) hash = digest;
    }
    const compressed = try c.fmt("{s}/Packages.xz", .{work});
    try c.download(try c.fmt("{s}/{s}", .{ base, index_name }), compressed);
    try verifyHash(c, compressed, hash orelse return error.IndexNotInSignedRelease);
    const index = try unpackIndex(c, compressed, try c.fmt("{s}/Packages", .{work}), index_name);
    var records = std.mem.splitSequence(u8, index, "\n\n");
    var matches: std.ArrayList(Candidate) = .empty;
    while (records.next()) |record| {
        if (!std.mem.eql(u8, foreign.debField(record, "Package") orelse "", o.name)) continue;
        const path = foreign.debField(record, "Filename") orelse return error.MissingPackageFilename;
        if (!sys.safePath(path)) return error.UnsafeRepositoryPath;
        const metadata: package.Metadata = .{
            .provider = o.provider,
            .repository = try c.fmt("{s}/{s}", .{ suite, component }),
            .name = o.name,
            .version = foreign.debField(record, "Version") orelse return error.MissingPackageVersion,
            .architecture = foreign.debField(record, "Architecture") orelse return error.MissingArchitecture,
            .description = foreign.debField(record, "Description") orelse "foreign binary package",
            .source = try c.fmt("{s}/{s}", .{ mirror, path }),
            .sha256 = foreign.debField(record, "SHA256") orelse "",
            .source_checksum = foreign.debField(record, "SHA256") orelse foreign.debField(record, "SHA512") orelse return error.MissingChecksum,
            .source_checksum_algorithm = if (foreign.debField(record, "SHA256") != null) "sha256" else "sha512",
            .signature_verified = true,
        };
        try package.validate(metadata);
        try matches.append(c.a, .{ .metadata = metadata, .filename = std.fs.path.basename(path), .original = record });
    }
    if (matches.items.len == 0) return error.PackageNotFound;
    if (matches.items.len == 1) return matches.items[0];
    for (matches.items, 1..) |m, i| try c.print("{d}: {s}\n", .{ i, m.metadata.version });
    const selection = try std.fmt.parseInt(usize, try c.prompt("Version number: "), 10);
    if (selection == 0 or selection > matches.items.len) return error.InvalidSelection;
    return matches.items[selection - 1];
}

fn element(xml: []const u8, tag: []const u8) ?[]const u8 {
    var offset: usize = 0;
    while (std.mem.indexOfScalarPos(u8, xml, offset, '<')) |start| {
        const begin = start + 1;
        if (std.mem.startsWith(u8, xml[begin..], tag) and begin + tag.len < xml.len and (xml[begin + tag.len] == '>' or xml[begin + tag.len] == ' ')) {
            const close = std.mem.indexOfScalarPos(u8, xml, begin, '>') orelse return null;
            const end = std.mem.indexOfScalarPos(u8, xml, close + 1, '<') orelse return null;
            return xml[close + 1 .. end];
        }
        offset = begin;
    }
    return null;
}

fn attribute(xml: []const u8, tag: []const u8, name: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (std.mem.indexOfScalarPos(u8, xml, pos, '<')) |start| {
        pos = start + 1;
        if (!std.mem.startsWith(u8, xml[pos..], tag)) continue;
        const next = pos + tag.len;
        if (next >= xml.len or (xml[next] != ' ' and xml[next] != '>')) continue;
        const end = std.mem.indexOfScalarPos(u8, xml, next, '>') orelse return null;
        var fields = std.mem.tokenizeAny(u8, xml[next..end], " \t\r\n");
        while (fields.next()) |field| {
            if (field.len < name.len + 3 or !std.mem.startsWith(u8, field, name) or field[name.len] != '=') continue;
            const quote = field[name.len + 1];
            if (quote != '"' and quote != '\'') return null;
            const finish = std.mem.indexOfScalarPos(u8, field, name.len + 2, quote) orelse return null;
            return field[name.len + 2 .. finish];
        }
        return null;
    }
    return null;
}

pub fn rpm(c: Context, o: Options, work: []const u8) !Candidate {
    const fedora = std.mem.eql(u8, o.provider, "fedora");
    if (o.suite != null) return error.RpmSuiteUnsupported;
    if (o.repo) |repo| {
        if (!std.mem.eql(u8, repo, if (fedora) "rawhide/Everything" else "tumbleweed/oss")) return error.UnsupportedRepository;
    }
    const mirror = std.mem.trimEnd(u8, o.mirror orelse if (fedora) "https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/x86_64/os" else "https://download.opensuse.org/tumbleweed/repo/oss", "/");
    const repomd = try c.fmt("{s}/repomd.xml", .{work});
    try c.download(try c.fmt("{s}/repodata/repomd.xml", .{mirror}), repomd);
    const xml = try c.read(repomd);
    var records = std.mem.splitSequence(u8, xml, "<data ");
    var path: ?[]const u8 = null;
    var hash: ?[]const u8 = null;
    while (records.next()) |record| {
        if (!std.mem.startsWith(u8, record, "type=\"primary\"") and !std.mem.startsWith(u8, record, "type='primary'")) continue;
        path = attribute(record, "location", "href");
        const algorithm = attribute(record, "checksum", "type") orelse "";
        if (!std.mem.eql(u8, algorithm, "sha256") and !std.mem.eql(u8, algorithm, "sha512")) return error.UnsupportedChecksum;
        hash = element(record, "checksum");
        break;
    }
    const location = path orelse return error.MissingPrimaryIndex;
    if (!sys.safePath(location)) return error.UnsafeRepositoryPath;
    const compressed = try c.fmt("{s}/primary.compressed", .{work});
    try c.download(try c.fmt("{s}/{s}", .{ mirror, location }), compressed);
    try verifyHash(c, compressed, hash orelse return error.MissingChecksum);
    const index = try unpackIndex(c, compressed, try c.fmt("{s}/primary.xml", .{work}), location);
    var packages = std.mem.splitSequence(u8, index, "<package ");
    while (packages.next()) |record| {
        if (!std.mem.eql(u8, element(record, "name") orelse "", o.name)) continue;
        const arch = element(record, "arch") orelse return error.MissingArchitecture;
        if (!std.mem.eql(u8, arch, "x86_64") and !std.mem.eql(u8, arch, "noarch")) continue;
        const package_path = attribute(record, "location", "href") orelse return error.MissingPackageFilename;
        if (!sys.safePath(package_path)) return error.UnsafeRepositoryPath;
        const m: package.Metadata = .{
            .provider = o.provider,
            .repository = o.repo orelse if (fedora) "rawhide/Everything" else "tumbleweed/oss",
            .name = o.name,
            .version = try c.fmt("{s}:{s}-{s}", .{
                attribute(record, "version", "epoch") orelse "0",
                attribute(record, "version", "ver") orelse return error.MissingPackageVersion,
                attribute(record, "version", "rel") orelse return error.MissingPackageVersion,
            }),
            .architecture = arch,
            .description = element(record, "summary") orelse "foreign binary package",
            .source = try c.fmt("{s}/{s}", .{ mirror, package_path }),
            .sha256 = if (std.mem.eql(u8, attribute(record, "checksum", "type") orelse "", "sha256")) element(record, "checksum") orelse return error.MissingChecksum else "",
            .source_checksum = element(record, "checksum") orelse return error.MissingChecksum,
            .source_checksum_algorithm = attribute(record, "checksum", "type") orelse return error.MissingChecksum,
        };
        if (!std.mem.eql(u8, m.source_checksum_algorithm, "sha256") and !std.mem.eql(u8, m.source_checksum_algorithm, "sha512")) return error.UnsupportedChecksum;
        try package.validate(m);
        return .{ .metadata = m, .filename = std.fs.path.basename(package_path), .original = record[0 .. std.mem.indexOf(u8, record, "</package>") orelse record.len] };
    }
    return error.PackageNotFound;
}

pub fn fetch(c: Context, candidate: *Candidate, o: Options, work: []const u8) ![]const u8 {
    const dest = try c.fmt("{s}/{s}", .{ work, candidate.filename });
    try c.download(candidate.metadata.source, dest);
    try verifyHash(c, dest, if (candidate.metadata.source_checksum.len > 0) candidate.metadata.source_checksum else candidate.metadata.sha256);
    candidate.metadata.sha256 = try c.checksum(dest);
    if (std.mem.eql(u8, o.provider, "fedora") or std.mem.eql(u8, o.provider, "opensuse")) {
        // This disposable RPM keyring contains trust keys, never installed packages.
        const trust = try c.fmt("{s}/rpm-trust", .{work});
        try std.Io.Dir.cwd().createDirPath(c.io, trust);
        try c.run(&.{ "rpmkeys", "--dbpath", trust, "--import", try c.absolute(o.keyring) });
        try c.run(&.{ "rpmkeys", "--dbpath", trust, "--define", "_pkgverify_level all", "--define", "_pkgverify_flags 0", "--checksig", dest });
        candidate.metadata.signature_verified = true;
    }
    return dest;
}

test "rpm XML fields" {
    const data = "<name>foo</name><version epoch=\"0\" ver=\"1.2\" rel=\"3\"/><location href=\"Packages/f/foo.rpm\"/>";
    try std.testing.expectEqualStrings("foo", element(data, "name").?);
    try std.testing.expectEqualStrings("1.2", attribute(data, "version", "ver").?);
    try std.testing.expectEqualStrings("Packages/f/foo.rpm", attribute(data, "location", "href").?);
}
