const std = @import("std");
const sys = @import("sys.zig");
const Context = sys.Context;

pub const Entry = struct {
    path: []const u8,
    link: []const u8,
    kind: u8,
    mode: u32,
    uid: u64,
    gid: u64,
    attributes: bool,
};

fn text(bytes: []const u8) []const u8 {
    return bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len];
}

fn number(bytes: []const u8) !u64 {
    if (bytes[0] & 128 != 0) {
        if (bytes[0] != 128) return error.UnsupportedTarNumber;
        var result: u64 = 0;
        for (bytes[1..]) |b| result = std.math.add(u64, try std.math.mul(u64, result, 256), b) catch return error.InvalidTarNumber;
        return result;
    }
    const value = std.mem.trim(u8, bytes, " \x00");
    return if (value.len == 0) 0 else std.fmt.parseInt(u64, value, 8);
}

fn clean(path: []const u8) []const u8 {
    var p = path;
    while (std.mem.startsWith(u8, p, "./")) p = p[2..];
    return std.mem.trimEnd(u8, p, "/");
}

pub fn audit(c: Context, tar_path: []const u8) ![]Entry {
    const file = try std.Io.Dir.cwd().openFile(c.io, tar_path, .{});
    defer file.close(c.io);
    var buffer: [65536]u8 = undefined;
    var fr = file.reader(c.io, &buffer);
    const reader = &fr.interface;
    var entries: std.ArrayList(Entry) = .empty;
    var override_path: ?[]const u8 = null;
    var override_link: ?[]const u8 = null;
    var override_size: ?u64 = null;
    var attributes = false;
    while (true) {
        var header: [512]u8 = undefined;
        try reader.readSliceAll(&header);
        if (std.mem.allEqual(u8, &header, 0)) break;
        var sum: u64 = 0;
        for (header, 0..) |b, i| sum += if (i >= 148 and i < 156) 32 else b;
        if (sum != try number(header[148..156])) return error.TarChecksum;
        const kind = header[156];
        var size = try number(header[124..136]);
        if (size > 16 * 1024 * 1024 * 1024) return error.ArchiveEntryTooLarge;
        if (kind == 'x' or kind == 'g' or kind == 'L' or kind == 'K') {
            if (size > 65536) return error.ArchiveMetadataTooLarge;
            const data = try c.a.alloc(u8, @intCast(size));
            try reader.readSliceAll(data);
            if (kind == 'L') {
                override_path = text(data);
            } else if (kind == 'K') {
                override_link = text(data);
            } else {
                var pos: usize = 0;
                while (pos < data.len) {
                    const space = std.mem.indexOfScalarPos(u8, data, pos, ' ') orelse return error.InvalidPax;
                    const length = try std.fmt.parseInt(usize, data[pos..space], 10);
                    if (length <= space - pos + 2 or length > data.len - pos) return error.InvalidPax;
                    const field = data[space + 1 .. pos + length - 1];
                    const eq = std.mem.indexOfScalar(u8, field, '=') orelse return error.InvalidPax;
                    const key = field[0..eq];
                    const value = field[eq + 1 ..];
                    if (kind == 'g' and (!std.mem.eql(u8, key, "mtime") and !std.mem.eql(u8, key, "atime") and !std.mem.eql(u8, key, "ctime"))) return error.UnsupportedGlobalPax;
                    if (std.mem.eql(u8, key, "path")) override_path = value;
                    if (std.mem.eql(u8, key, "linkpath")) override_link = value;
                    if (std.mem.eql(u8, key, "size")) override_size = try std.fmt.parseInt(u64, value, 10);
                    if (std.mem.indexOf(u8, key, "xattr") != null or std.mem.indexOf(u8, key, "acl") != null) attributes = true;
                    if (std.mem.startsWith(u8, key, "GNU.sparse")) return error.UnsupportedSparseArchive;
                    pos += length;
                }
            }
        } else {
            size = override_size orelse size;
            const prefix = if (std.mem.startsWith(u8, header[257..263], "ustar")) text(header[345..500]) else "";
            const base = text(header[0..100]);
            const name = override_path orelse if (prefix.len == 0) base else try c.fmt("{s}/{s}", .{ prefix, base });
            const path = clean(name);
            if (path.len > 0 and !std.mem.eql(u8, path, ".")) {
                if (!sys.safePath(path)) return error.UnsafeArchivePath;
                if (kind != 0 and kind != '0' and kind != '1' and kind != '2' and kind != '5') return error.SpecialFileRequiresManualHandling;
                const link = override_link orelse text(header[157..257]);
                if (kind == '1' and !sys.safePath(link)) return error.UnsafeHardlink;
                for (link) |ch| if (ch < 32 or ch == 127) return error.InvalidLink;
                try entries.append(c.a, .{
                    .path = try c.a.dupe(u8, path),
                    .link = try c.a.dupe(u8, clean(link)),
                    .kind = if (kind == 0) '0' else kind,
                    .mode = @intCast(try number(header[100..108])),
                    .uid = try number(header[108..116]),
                    .gid = try number(header[116..124]),
                    .attributes = attributes,
                });
            }
            try reader.discardAll64(size);
            override_path = null;
            override_link = null;
            override_size = null;
            attributes = false;
        }
        try reader.discardAll64((512 - size % 512) % 512);
    }
    var seen: std.StringHashMap(Entry) = .init(c.a);
    for (entries.items) |entry| {
        if (seen.get(entry.path)) |old| {
            if (old.kind != '5' or entry.kind != '5') return error.DuplicateArchivePath;
        }
        try seen.put(entry.path, entry);
    }
    for (entries.items) |entry| {
        var parent = std.fs.path.dirname(entry.path);
        while (parent) |p| {
            if (seen.get(p)) |other| if (other.kind != '5') return error.ArchivePathThroughLink;
            parent = std.fs.path.dirname(p);
        }
        if (entry.kind == '1') {
            const target = seen.get(entry.link) orelse return error.MissingHardlinkTarget;
            if (target.kind != '0') return error.UnsafeHardlink;
        }
    }
    return entries.toOwnedSlice(c.a);
}

pub const Archive = struct { tar: []const u8, entries: []Entry };

pub fn normalize(c: Context, source: []const u8, work: []const u8) !Archive {
    const absolute = try c.absolute(source);
    // Inspect source names too: normalization must not hide absolute paths.
    const listing = try c.capture(&.{ "bsdtar", "-tf", absolute });
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        if (line.len > 0 and !sys.safePath(line)) return error.UnsafeArchivePath;
    }
    const tar = try c.fmt("{s}/payload.tar", .{work});
    try c.run(&.{ "bsdtar", "-cf", tar, "--format", "pax", try c.fmt("@{s}", .{absolute}) });
    return .{ .tar = tar, .entries = try audit(c, tar) };
}

pub fn extract(c: Context, archive: Archive, destination: []const u8, allow_privileged: bool) !void {
    for (archive.entries) |entry| {
        if (entry.attributes) return error.ExtendedAttributesRequireManualHandling;
        if (entry.uid != 0 or entry.gid != 0) return error.ForeignOwnershipRequiresManualHandling;
        if (entry.mode & 0o6000 != 0) {
            try c.print("privileged mode {o}: {s}\n", .{ entry.mode, entry.path });
            if (!allow_privileged) return error.PrivilegedModeRequiresExplicitOption;
        }
    }
    try std.Io.Dir.cwd().createDirPath(c.io, destination);
    try c.run(&.{ "bsdtar", "-xpf", archive.tar, "-C", destination, "--no-same-owner", "--no-acls", "--no-xattrs", "--no-fflags" });
}

test "octal tar numbers" {
    try std.testing.expectEqual(@as(u64, 493), try number("0000755\x00"));
    try std.testing.expectEqual(@as(u64, 0), try number("\x00\x00\x00"));
}
