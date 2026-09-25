const std = @import("std");
const sys = @import("sys.zig");
const archive = @import("archive.zig");
const package = @import("package.zig");
const Context = sys.Context;

pub fn debField(data: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(line[0..colon], key)) return std.mem.trim(u8, line[colon + 1 ..], " \r");
    }
    return null;
}

pub fn stageDeb(c: Context, source: []const u8, provider: []const u8, stage: []const u8, privileged: bool) !void {
    const work = try c.temp();
    defer std.Io.Dir.cwd().deleteTree(c.io, work) catch {};
    const input = try c.absolute(source);
    const list = try c.capture(&.{ "bsdtar", "-tf", input });
    var lines = std.mem.splitScalar(u8, list, '\n');
    var control: ?[]const u8 = null;
    var data: ?[]const u8 = null;
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "control.tar")) {
            if (control != null or !sys.safeName(line)) return error.InvalidDeb;
            control = line;
        }
        if (std.mem.startsWith(u8, line, "data.tar")) {
            if (data != null or !sys.safeName(line)) return error.InvalidDeb;
            data = line;
        }
    }
    const version = try c.capture(&.{ "bsdtar", "-xOf", input, "debian-binary" });
    if (!std.mem.eql(u8, std.mem.trim(u8, version, "\r\n"), "2.0")) return error.UnsupportedDebVersion;
    const control_path = try c.fmt("{s}/control.archive", .{work});
    const data_path = try c.fmt("{s}/data.archive", .{work});
    try c.saveOutput(&.{ "bsdtar", "-xOf", input, control orelse return error.InvalidDeb }, control_path);
    try c.saveOutput(&.{ "bsdtar", "-xOf", input, data orelse return error.InvalidDeb }, data_path);
    const control_work = try c.fmt("{s}/control-work", .{work});
    try std.Io.Dir.cwd().createDirPath(c.io, control_work);
    const ca = try archive.normalize(c, control_path, control_work);
    for (ca.entries) |entry| if (entry.kind != '0' and entry.kind != '5') return error.InvalidDebControl;
    const control_root = try c.fmt("{s}/control", .{work});
    try archive.extract(c, ca, control_root, false);
    const metadata = try c.read(try c.fmt("{s}/control", .{control_root}));
    const m: package.Metadata = .{
        .provider = provider,
        .name = debField(metadata, "Package") orelse return error.MissingPackageName,
        .version = debField(metadata, "Version") orelse return error.MissingPackageVersion,
        .architecture = debField(metadata, "Architecture") orelse return error.MissingArchitecture,
        .description = debField(metadata, "Description") orelse "foreign binary package",
        .source = input,
        .sha256 = try c.checksum(input),
    };
    try package.validate(m);
    try std.Io.Dir.cwd().createDir(c.io, stage, .default_dir);
    const a = try archive.normalize(c, data_path, work);
    try archive.extract(c, a, try c.fmt("{s}/root", .{stage}), privileged);
    try package.finishStage(c, stage, m, a.entries);
    try c.run(&.{ "cp", "-a", "--", control_root, try c.fmt("{s}/root/usr/doc/{s}/holypkg/debian-control", .{ stage, m.name }) });
}

pub fn stageRpm(c: Context, source: []const u8, provider: []const u8, stage: []const u8, privileged: bool) !void {
    const work = try c.temp();
    defer std.Io.Dir.cwd().deleteTree(c.io, work) catch {};
    const input = try c.absolute(source);
    const raw = try c.capture(&.{ "rpm", "-qp", "--queryformat", "%{NAME}\n%{EPOCHNUM}:%{VERSION}-%{RELEASE}\n%{ARCH}\n%{SUMMARY}\n", "--", input });
    var lines = std.mem.splitScalar(u8, raw, '\n');
    const m: package.Metadata = .{
        .provider = provider,
        .name = lines.next() orelse return error.MissingPackageName,
        .version = lines.next() orelse return error.MissingPackageVersion,
        .architecture = lines.next() orelse return error.MissingArchitecture,
        .description = lines.next() orelse "foreign binary package",
        .source = input,
        .sha256 = try c.checksum(input),
    };
    try package.validate(m);
    const scripts = try c.capture(&.{ "rpm", "-qp", "--scripts", "--triggers", "--", input });
    // rpm2cpio only extracts payload; rpm is never asked to install a package.
    const payload = try c.fmt("{s}/payload.cpio", .{work});
    try c.saveOutput(&.{ "rpm2cpio", input }, payload);
    const a = try archive.normalize(c, payload, work);
    try std.Io.Dir.cwd().createDir(c.io, stage, .default_dir);
    try archive.extract(c, a, try c.fmt("{s}/root", .{stage}), privileged);
    try package.finishStage(c, stage, m, a.entries);
    try c.write(try c.fmt("{s}/root/usr/doc/{s}/holypkg/rpm-scripts.txt", .{ stage, m.name }), scripts);
    try c.write(try c.fmt("{s}/root/usr/doc/{s}/holypkg/rpm-info.txt", .{ stage, m.name }), try c.capture(&.{ "rpm", "-qpi", "--", input }));
}

pub fn stageGeneric(c: Context, source: []const u8, stage: []const u8, m: package.Metadata, prefix: []const u8, privileged: bool) !void {
    try package.validate(m);
    if (!std.mem.eql(u8, prefix, "/") and (!std.mem.startsWith(u8, prefix, "/") or !sys.safePath(prefix[1..]))) return error.InvalidPrefix;
    const work = try c.temp();
    defer std.Io.Dir.cwd().deleteTree(c.io, work) catch {};
    const a = try archive.normalize(c, source, work);
    try std.Io.Dir.cwd().createDir(c.io, stage, .default_dir);
    const relative = std.mem.trim(u8, prefix, "/");
    const root = try c.fmt("{s}/root", .{stage});
    const destination = if (relative.len == 0) root else try c.fmt("{s}/{s}", .{ root, relative });
    try archive.extract(c, a, destination, privileged);
    for (a.entries) |*entry| {
        if (relative.len > 0) entry.path = try c.fmt("{s}/{s}", .{ relative, entry.path });
    }
    try package.finishStage(c, stage, m, a.entries);
}

test "debian fields" {
    try std.testing.expectEqualStrings("foo", debField("Package: foo\nVersion: 1.2-3\n", "Package").?);
}
