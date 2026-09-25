const std = @import("std");
const sys = @import("sys.zig");
const package = @import("package.zig");
const archive = @import("archive.zig");
const pacman = @import("pacman.zig");
const foreign = @import("foreign.zig");
const inspect = @import("inspect.zig");

const usage =
    \\holypkg - foreign binary packages to native Slackware packages
    \\
    \\holypkg arch|artix PACKAGE [--repo REPO] [--testing]
    \\holypkg info|deps|files|fetch arch|artix PACKAGE
    \\holypkg convert FILE --provider PROVIDER [--stage [DIRECTORY]]
    \\holypkg pack STAGE [--output DIRECTORY]
    \\holypkg inspect|scripts FILE --provider PROVIDER
    \\holypkg collisions STAGE [--root ROOT]
    \\holypkg github OWNER/REPO --asset NAME --name NAME --version VERSION --prefix PATH
    \\holypkg url HTTPS_URL --name NAME --version VERSION --prefix PATH --sha256 HASH
    \\
    \\Options: --keyring FILE, --mirror URL, --output DIRECTORY,
    \\         --allow-privileged, --install, --force, --release TAG
    \\
    \\No dependency resolution. No automatic foreign scripts. No package database.
    \\Unsigned URLs require --sha256. Generic archives require an explicit prefix.
    \\
;

const Options = struct {
    positional: []const []const u8,
    provider: ?[]const u8 = null,
    repo: ?[]const u8 = null,
    mirror: ?[]const u8 = null,
    keyring: ?[]const u8 = null,
    output: []const u8 = ".",
    stage: ?[]const u8 = null,
    keep_stage: bool = false,
    testing: bool = false,
    privileged: bool = false,
    install: bool = false,
    force: bool = false,
    root: []const u8 = "/",
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    prefix: ?[]const u8 = null,
    sha256: ?[]const u8 = null,
    asset: ?[]const u8 = null,
    release: []const u8 = "latest",

    fn parse(c: sys.Context, args: []const []const u8) !Options {
        var o: Options = .{ .positional = &.{} };
        var positional: std.ArrayList([]const u8) = .empty;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "--testing")) {
                o.testing = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--allow-privileged")) {
                o.privileged = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--install")) {
                o.install = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--force")) {
                o.force = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--stage")) {
                o.keep_stage = true;
                if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                    i += 1;
                    o.stage = args[i];
                }
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--") and !std.mem.eql(u8, arg, "--help")) {
                if (i + 1 >= args.len or std.mem.startsWith(u8, args[i + 1], "--")) return error.MissingOptionValue;
                i += 1;
                const val = args[i];
                if (std.mem.eql(u8, arg, "--provider")) o.provider = val else if (std.mem.eql(u8, arg, "--repo")) o.repo = val else if (std.mem.eql(u8, arg, "--mirror")) o.mirror = val else if (std.mem.eql(u8, arg, "--keyring")) o.keyring = val else if (std.mem.eql(u8, arg, "--output")) o.output = val else if (std.mem.eql(u8, arg, "--root")) o.root = val else if (std.mem.eql(u8, arg, "--name")) o.name = val else if (std.mem.eql(u8, arg, "--version")) o.version = val else if (std.mem.eql(u8, arg, "--prefix")) o.prefix = val else if (std.mem.eql(u8, arg, "--sha256")) o.sha256 = val else if (std.mem.eql(u8, arg, "--asset")) o.asset = val else if (std.mem.eql(u8, arg, "--release")) o.release = val else return error.UnknownOption;
            } else try positional.append(c.a, arg);
        }
        o.positional = try positional.toOwnedSlice(c.a);
        if (o.keep_stage and o.install) return error.StageDoesNotInstall;
        return o;
    }
};

fn is(name: []const u8, wanted: []const u8) bool {
    return std.mem.eql(u8, name, wanted);
}

fn convert(c: sys.Context, source: []const u8, provider: []const u8, stage: []const u8, o: Options, metadata: ?package.Metadata) !void {
    if (is(provider, "arch") or is(provider, "artix")) {
        try package.stagePacman(c, source, provider, stage, o.privileged, metadata);
    } else if (is(provider, "debian") or is(provider, "ubuntu")) {
        try foreign.stageDeb(c, source, provider, stage, o.privileged);
    } else if (is(provider, "fedora") or is(provider, "opensuse")) {
        try foreign.stageRpm(c, source, provider, stage, o.privileged);
    } else if (is(provider, "github") or is(provider, "url")) {
        const m: package.Metadata = metadata orelse .{
            .provider = provider,
            .name = o.name orelse return error.NameRequired,
            .version = o.version orelse return error.VersionRequired,
            .architecture = "x86_64",
            .source = try c.absolute(source),
            .sha256 = try c.checksum(source),
        };
        try foreign.stageGeneric(c, source, stage, m, o.prefix orelse return error.PrefixRequired, o.privileged);
    } else return error.UnknownProvider;
}

fn finish(c: sys.Context, stage: []const u8, o: Options) !void {
    const root = try c.fmt("{s}/root", .{stage});
    if (o.keep_stage) return inspect.tree(c, root);
    if (o.install) {
        if (!is(o.root, "/")) return error.InstallIntoAlternateRootUnsupported;
        const count = try inspect.collisions(c, root, "/");
        if (count > 0 and !o.force) return error.FilesystemCollisions;
    }
    const output = try package.pack(c, stage, o.output);
    if (o.install) try c.run(&.{ "doas", "installpkg", output });
    try std.Io.Dir.cwd().deleteTree(c.io, stage);
}

fn githubUrl(c: sys.Context, repository: []const u8, o: Options, work: []const u8) ![]const u8 {
    var parts = std.mem.splitScalar(u8, repository, '/');
    const owner = parts.next() orelse return error.InvalidRepository;
    const repo = parts.next() orelse return error.InvalidRepository;
    if (!sys.safeName(owner) or !sys.safeName(repo) or parts.next() != null) return error.InvalidRepository;
    const asset = o.asset orelse return error.AssetRequired;
    if (!sys.safeName(o.release)) return error.InvalidRelease;
    const endpoint = if (is(o.release, "latest")) "latest" else try c.fmt("tags/{s}", .{o.release});
    const path = try c.fmt("{s}/release.json", .{work});
    try c.download(try c.fmt("https://api.github.com/repos/{s}/releases/{s}", .{ repository, endpoint }), path);
    const parsed = try std.json.parseFromSlice(std.json.Value, c.a, try c.read(path), .{ .allocate = .alloc_always });
    if (parsed.value != .object) return error.InvalidGithubResponse;
    const assets = parsed.value.object.get("assets") orelse return error.InvalidGithubResponse;
    if (assets != .array) return error.InvalidGithubResponse;
    for (assets.array.items) |entry| {
        if (entry != .object) return error.InvalidGithubResponse;
        const name = entry.object.get("name") orelse continue;
        const url = entry.object.get("browser_download_url") orelse continue;
        if (name == .string and url == .string and is(name.string, asset)) return url.string;
    }
    return error.AssetNotFound;
}

fn execute(c: sys.Context, args: []const []const u8) !void {
    const o = try Options.parse(c, args);
    const p = o.positional;
    if (p.len == 0 or is(p[0], "--help")) return c.print("{s}", .{usage});
    if (p.len < 2) return error.MissingArgument;
    const action = p[0];
    if (is(action, "pack")) {
        _ = try package.pack(c, p[1], o.output);
        return;
    }
    if (is(action, "collisions")) {
        if (try inspect.collisions(c, try c.fmt("{s}/root", .{p[1]}), o.root) > 0) return error.FilesystemCollisions;
        return;
    }
    const work = try c.temp();
    defer std.Io.Dir.cwd().deleteTree(c.io, work) catch {};
    const stage = o.stage orelse try c.fmt("{s}/stage", .{try c.temp()});
    // A failed conversion retains its stage for diagnosis; no installed database is created.
    if (is(action, "convert") or is(action, "inspect") or is(action, "scripts")) {
        try convert(c, p[1], o.provider orelse return error.ProviderRequired, stage, o, null);
        if (is(action, "inspect")) {
            try inspect.elf(c, try c.fmt("{s}/root", .{stage}));
            try std.Io.Dir.cwd().deleteTree(c.io, stage);
        } else if (is(action, "scripts")) {
            const m = try package.readStage(c, stage);
            const doc = try c.fmt("{s}/root/usr/doc/{s}/holypkg", .{ stage, m.name });
            const names = [_][]const u8{ "original/.INSTALL", "rpm-scripts.txt", "debian-control/preinst", "debian-control/postinst", "debian-control/prerm", "debian-control/postrm", "debian-control/config", "debian-control/triggers" };
            for (names) |name| {
                const data = c.read(try c.fmt("{s}/{s}", .{ doc, name })) catch |err| switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                };
                try c.print("{s}:\n{s}\n", .{ name, data });
            }
            try std.Io.Dir.cwd().deleteTree(c.io, stage);
        } else try finish(c, stage, o);
        return;
    }
    if (is(action, "github") or is(action, "url")) {
        const url = if (is(action, "github")) try githubUrl(c, p[1], o, work) else p[1];
        const expected = o.sha256 orelse return error.ExpectedChecksumRequired;
        const path = try c.fmt("{s}/artifact", .{work});
        try c.download(url, path);
        const digest = try c.checksum(path);
        if (!std.ascii.eqlIgnoreCase(expected, digest)) return error.ChecksumMismatch;
        const m: package.Metadata = .{
            .provider = action,
            .name = o.name orelse return error.NameRequired,
            .version = o.version orelse return error.VersionRequired,
            .architecture = "x86_64",
            .source = url,
            .sha256 = digest,
        };
        try convert(c, path, action, stage, o, m);
        try finish(c, stage, o);
        return;
    }
    const query = is(action, "info") or is(action, "deps") or is(action, "files") or is(action, "fetch");
    if (query and p.len != 3) return error.ExpectedProviderAndPackage;
    const provider = if (query) p[1] else action;
    const name = if (query) p[2] else p[1];
    const options: pacman.Options = .{
        .provider = provider,
        .name = name,
        .repo = o.repo,
        .mirror = o.mirror,
        .testing = o.testing,
        .keyring = o.keyring orelse try c.fmt("/etc/holypkg/keys/{s}.gpg", .{provider}),
    };
    var candidate = try pacman.resolve(c, options, work);
    if (is(action, "info")) return c.print("{s}\nRepository information; package signature is verified when fetched.\n", .{try std.json.Stringify.valueAlloc(c.a, candidate.metadata, .{ .whitespace = .indent_2 })});
    if (is(action, "deps")) return pacman.deps(c, candidate);
    const source = try pacman.fetch(c, &candidate, options, work);
    if (is(action, "fetch")) {
        try std.Io.Dir.cwd().createDirPath(c.io, o.output);
        const output = try c.fmt("{s}/{s}", .{ o.output, candidate.filename });
        try c.run(&.{ "cp", "--no-clobber", "--", source, output });
        try c.run(&.{ "cp", "--no-clobber", "--", try c.fmt("{s}.sig", .{source}), try c.fmt("{s}.sig", .{output}) });
        return;
    }
    try convert(c, source, provider, stage, o, candidate.metadata);
    if (is(action, "files")) {
        try inspect.tree(c, try c.fmt("{s}/root", .{stage}));
        try std.Io.Dir.cwd().deleteTree(c.io, stage);
    } else try finish(c, stage, o);
}

pub fn main(init: std.process.Init) !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const c: sys.Context = .{ .a = arena.allocator(), .io = init.io };
    const args = try init.minimal.args.toSlice(c.a);
    execute(c, args) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(c.io, try c.fmt("holypkg: {s}\n", .{@errorName(err)}));
        return 1;
    };
    return 0;
}

test {
    std.testing.refAllDecls(sys);
    std.testing.refAllDecls(package);
    std.testing.refAllDecls(archive);
    std.testing.refAllDecls(pacman);
    std.testing.refAllDecls(foreign);
}
