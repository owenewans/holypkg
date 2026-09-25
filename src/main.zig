const std = @import("std");
const sys = @import("sys.zig");
const package = @import("package.zig");
const archive = @import("archive.zig");
const pacman = @import("pacman.zig");
const foreign = @import("foreign.zig");
const inspect = @import("inspect.zig");
const repositories = @import("repository.zig");
const keys = @import("keys.zig");

const usage =
    \\holypkg - foreign binary packages to native Slackware packages
    \\
    \\holypkg arch|artix PACKAGE [--repo REPO] [--testing]
    \\holypkg info|deps|files|fetch PROVIDER PACKAGE
    \\holypkg debian|ubuntu|fedora|opensuse PACKAGE [--suite SUITE] [--repo REPO]
    \\holypkg key add FILE --fingerprint HEX --keyring OUTPUT
    \\holypkg convert FILE --provider PROVIDER [--stage [DIRECTORY]]
    \\holypkg pack STAGE [--output DIRECTORY]
    \\holypkg inspect|scripts FILE --provider PROVIDER
    \\holypkg collisions STAGE [--root ROOT]
    \\holypkg github OWNER/REPO --asset NAME --name NAME --version VERSION --prefix PATH
    \\holypkg url HTTPS_URL --name NAME --version VERSION --prefix PATH --sha256 HASH
    \\
    \\Options: --keyring FILE, --mirror URL, --output DIRECTORY,
    \\         --allow-privileged, --owner root, --install, --force, --release TAG
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
    suite: ?[]const u8 = null,
    fingerprint: ?[]const u8 = null,
    owner: ?[]const u8 = null,

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
                const fields = .{ .{ "--provider", "provider" }, .{ "--repo", "repo" }, .{ "--mirror", "mirror" }, .{ "--keyring", "keyring" }, .{ "--output", "output" }, .{ "--root", "root" }, .{ "--name", "name" }, .{ "--version", "version" }, .{ "--prefix", "prefix" }, .{ "--sha256", "sha256" }, .{ "--asset", "asset" }, .{ "--release", "release" }, .{ "--suite", "suite" }, .{ "--fingerprint", "fingerprint" }, .{ "--owner", "owner" } };
                var recognized = false;
                inline for (fields) |field| {
                    if (std.mem.eql(u8, arg, field[0])) {
                        @field(o, field[1]) = val;
                        recognized = true;
                    }
                }
                if (!recognized) return error.UnknownOption;
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
    if (o.owner) |owner| if (!is(owner, "root")) return error.UnsupportedOwnershipRule;
    const extraction: archive.ExtractOptions = .{ .privileged = o.privileged, .root_owner = o.owner != null };
    if (is(provider, "arch") or is(provider, "artix")) {
        try package.stagePacman(c, source, provider, stage, extraction, metadata);
    } else if (is(provider, "debian") or is(provider, "ubuntu")) {
        try foreign.stageDeb(c, source, provider, stage, extraction);
    } else if (is(provider, "fedora") or is(provider, "opensuse")) {
        try foreign.stageRpm(c, source, provider, stage, extraction);
    } else if (is(provider, "github") or is(provider, "url")) {
        const m: package.Metadata = metadata orelse .{
            .provider = provider,
            .name = o.name orelse return error.NameRequired,
            .version = o.version orelse return error.VersionRequired,
            .architecture = "x86_64",
            .source = try c.absolute(source),
            .sha256 = try c.checksum(source),
        };
        try foreign.stageGeneric(c, source, stage, m, o.prefix orelse return error.PrefixRequired, extraction);
    } else return error.UnknownProvider;
    if (metadata) |m| {
        const actual = try package.readStage(c, stage);
        if (!is(actual.name, m.name) or !is(actual.version, m.version) or !is(actual.sha256, m.sha256)) return error.RepositoryMetadataMismatch;
        var provenance = m;
        provenance.ownership = actual.ownership;
        const json = try std.json.Stringify.valueAlloc(c.a, provenance, .{ .whitespace = .indent_2 });
        try c.write(try c.fmt("{s}/package.json", .{stage}), json);
        try c.write(try c.fmt("{s}/root/usr/doc/{s}/holypkg/provenance.json", .{ stage, m.name }), json);
    }
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
    const readonly = is(action, "info") or is(action, "deps") or is(action, "files") or is(action, "fetch") or is(action, "inspect") or is(action, "scripts") or is(action, "collisions") or is(action, "key");
    if (readonly and (o.install or o.keep_stage or o.force)) return error.OptionNotValidForCommand;
    if (o.force and !o.install) return error.ForceRequiresInstall;
    if (is(action, "key")) {
        if (p.len != 3 or !is(p[1], "add")) return error.ExpectedKeyAddFile;
        return keys.add(c, p[2], o.fingerprint orelse return error.FullFingerprintRequired, o.keyring orelse return error.KeyringOutputRequired);
    }
    if (is(action, "pack")) {
        if (p.len != 2 or o.keep_stage) return error.InvalidPackArguments;
        if (o.install) {
            if (!is(o.root, "/")) return error.InstallIntoAlternateRootUnsupported;
            const count = try inspect.collisions(c, try c.fmt("{s}/root", .{p[1]}), "/");
            if (count > 0 and !o.force) return error.FilesystemCollisions;
        }
        const output = try package.pack(c, p[1], o.output);
        if (o.install) try c.run(&.{ "doas", "installpkg", output });
        return;
    }
    if (is(action, "collisions")) {
        if (try inspect.collisions(c, try c.fmt("{s}/root", .{p[1]}), o.root) > 0) return error.FilesystemCollisions;
        return;
    }
    const work = try c.temp();
    defer std.Io.Dir.cwd().deleteTree(c.io, work) catch {};
    const stage = o.stage orelse try c.fmt("{s}/stage", .{try c.temp()});
    // retain a failed conversion for inspection.
    if (is(action, "convert") or is(action, "inspect") or is(action, "scripts")) {
        if (p.len != 2) return error.UnexpectedArgument;
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
        if (p.len != 2) return error.UnexpectedArgument;
        const url = if (is(action, "github")) try githubUrl(c, p[1], o, work) else p[1];
        const expected = o.sha256 orelse return error.ExpectedChecksumRequired;
        const path = try c.fmt("{s}/artifact", .{work});
        try c.download(url, path);
        const digest = try c.checksum(path);
        if (!std.ascii.eqlIgnoreCase(expected, digest)) return error.ChecksumMismatch;
        const m: package.Metadata = .{
            .provider = action,
            .repository = if (is(action, "github")) try c.fmt("{s}@{s}", .{ p[1], o.release }) else "direct",
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
    if (!query and p.len != 2) return error.UnexpectedArgument;
    const provider = if (query) p[1] else action;
    const name = if (query) p[2] else p[1];
    if (is(provider, "debian") or is(provider, "ubuntu") or is(provider, "fedora") or is(provider, "opensuse")) {
        const opts: repositories.Options = .{
            .provider = provider,
            .name = name,
            .repo = o.repo,
            .suite = o.suite,
            .mirror = o.mirror,
            .keyring = o.keyring orelse try c.fmt("/etc/holypkg/keys/{s}.{s}", .{ provider, if (is(provider, "debian") or is(provider, "ubuntu")) "gpg" else "asc" }),
        };
        var candidate = if (is(provider, "debian") or is(provider, "ubuntu")) try repositories.deb(c, opts, work) else try repositories.rpm(c, opts, work);
        if (is(action, "info")) return c.print("{s}\n", .{try std.json.Stringify.valueAlloc(c.a, candidate.metadata, .{ .whitespace = .indent_2 })});
        if (is(action, "deps")) return c.print("Source repository metadata (no dependencies installed):\n{s}\n", .{candidate.original});
        const source = try repositories.fetch(c, &candidate, opts, work);
        if (is(action, "fetch")) {
            try std.Io.Dir.cwd().createDirPath(c.io, o.output);
            try c.copyNew(source, try c.fmt("{s}/{s}", .{ o.output, candidate.filename }));
            return;
        }
        var conversion = c;
        conversion.quiet = is(action, "files");
        try convert(conversion, source, provider, stage, o, candidate.metadata);
        if (is(action, "files")) {
            try c.print("{s}", .{try c.read(try c.fmt("{s}/payload.list", .{stage}))});
            try std.Io.Dir.cwd().deleteTree(c.io, stage);
        } else try finish(c, stage, o);
        return;
    }
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
        try c.copyNew(source, output);
        try c.copyNew(try c.fmt("{s}.sig", .{source}), try c.fmt("{s}.sig", .{output}));
        return;
    }
    var conversion = c;
    conversion.quiet = is(action, "files");
    try convert(conversion, source, provider, stage, o, candidate.metadata);
    if (is(action, "files")) {
        try c.print("{s}", .{try c.read(try c.fmt("{s}/payload.list", .{stage}))});
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
    std.testing.refAllDecls(repositories);
}
