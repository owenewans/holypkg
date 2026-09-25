const std = @import("std");
const sys = @import("sys.zig");
const Context = sys.Context;

pub fn files(c: Context, root: []const u8) ![]const u8 {
    return c.capture(&.{ "find", root, "-mindepth", "1", "-printf", "%y %P\x00" });
}

pub fn tree(c: Context, root: []const u8) !void {
    var it = std.mem.splitScalar(u8, try files(c, root), 0);
    while (it.next()) |item| if (item.len > 0) {
        try c.print("{s}\n", .{item});
    };
}

pub fn elf(c: Context, root: []const u8) !void {
    const libraries = c.capture(&.{ "ldconfig", "-p" }) catch "";
    var it = std.mem.splitScalar(u8, try files(c, root), 0);
    while (it.next()) |item| {
        if (item.len < 3 or item[0] != 'f') continue;
        const path = try c.fmt("{s}/{s}", .{ root, item[2..] });
        const file = try std.Io.Dir.cwd().openFile(c.io, path, .{});
        var buf: [64]u8 = undefined;
        var reader = file.reader(c.io, &buf);
        var magic: [4]u8 = undefined;
        const length = try reader.interface.readSliceShort(&magic);
        file.close(c.io);
        if (length != 4 or !std.mem.eql(u8, &magic, "\x7fELF")) continue;
        try c.print("\nELF: /{s}\n", .{item[2..]});
        const header = try c.capture(&.{ "readelf", "-hW", "--", path });
        const program = try c.capture(&.{ "readelf", "-lW", "--", path });
        const dynamic = try c.capture(&.{ "readelf", "-dW", "--", path });
        const versions = try c.capture(&.{ "readelf", "-VW", "--", path });
        for ([_][]const u8{ header, program, dynamic, versions }) |output| {
            var lines = std.mem.splitScalar(u8, output, '\n');
            while (lines.next()) |line| {
                if (std.mem.indexOf(u8, line, "Machine:") != null or
                    std.mem.indexOf(u8, line, "Class:") != null or
                    std.mem.indexOf(u8, line, "interpreter:") != null or
                    std.mem.indexOf(u8, line, "NEEDED") != null or
                    std.mem.indexOf(u8, line, "RPATH") != null or
                    std.mem.indexOf(u8, line, "RUNPATH") != null or
                    std.mem.indexOf(u8, line, "Name: GLIBC") != null or
                    std.mem.indexOf(u8, line, "Name: CXXABI") != null)
                {
                    try c.print("{s}\n", .{std.mem.trim(u8, line, " ")});
                }
                if (std.mem.indexOf(u8, line, "NEEDED") != null) {
                    const start = std.mem.indexOfScalar(u8, line, '[') orelse continue;
                    const end = std.mem.indexOfScalarPos(u8, line, start, ']') orelse continue;
                    const lib = line[start + 1 .. end];
                    if (std.mem.indexOf(u8, libraries, try c.fmt("{s} ", .{lib})) == null)
                        try c.print("not found in host ldconfig cache: {s} (RPATH/staged libraries not resolved)\n", .{lib});
                }
            }
        }
    }
}

pub fn collisions(c: Context, root: []const u8, host: []const u8) !usize {
    const db = try c.fmt("{s}/var/lib/pkgtools/packages", .{std.mem.trimEnd(u8, host, "/")});
    var owners: std.StringHashMap([]const u8) = .init(c.a);
    const names = c.capture(&.{ "find", db, "-maxdepth", "1", "-type", "f", "-printf", "%f\x00" }) catch return error.PkgtoolsDatabaseUnavailable;
    var packages = std.mem.splitScalar(u8, names, 0);
    while (packages.next()) |name| {
        if (name.len == 0) continue;
        const data = try c.read(try c.fmt("{s}/{s}", .{ db, name }));
        const start = std.mem.indexOf(u8, data, "FILE LIST:\n") orelse continue;
        var list = std.mem.splitScalar(u8, data[start + 11 ..], '\n');
        while (list.next()) |line| {
            var path = line;
            while (std.mem.startsWith(u8, path, "./")) path = path[2..];
            if (path.len == 0 or std.mem.endsWith(u8, path, "/")) continue;
            if (owners.get(path)) |previous| {
                try owners.put(path, try c.fmt("{s}, {s}", .{ previous, name }));
            } else try owners.put(path, name);
        }
    }
    var count: usize = 0;
    var paths = std.mem.splitScalar(u8, try files(c, root), 0);
    while (paths.next()) |item| {
        if (item.len < 3 or std.mem.startsWith(u8, item[2..], "install/")) continue;
        const path = item[2..];
        const full = try c.fmt("{s}/{s}", .{ std.mem.trimEnd(u8, host, "/"), path });
        const stat = std.Io.Dir.cwd().statFile(c.io, full, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        if (item[0] == 'd' and stat.kind == .directory) continue;
        count += 1;
        try c.print("/{s}\n    already owned by: {s}\n", .{ path, owners.get(path) orelse "unmanaged filesystem entry" });
    }
    return count;
}
