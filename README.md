# holypkg

Convert explicitly selected foreign binary packages into ordinary Slackware
packages. Written in Zig; installation remains the responsibility of pkgtools.

**Development status:** implementation and validation are in progress. This is
not a finished release. Do not use development builds to modify a production
system. See [TESTING.md](TESTING.md) for evidence and outstanding coverage.

## Build

Requires Zig 0.16.0:

```sh
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
zig build test
python3 tests/archive.py zig-out/bin/holypkg
```

The executable is static. Runtime tools are supplied by the host: `curl`,
`bsdtar`, compression tools, GnuPG, `makepkg`, coreutils and `find`. RPM input
also needs `rpm`/`rpm2cpio`; ELF diagnostics use `readelf`. Non-root packaging
sets root ownership in GNU tar headers through `makepkg`, preserving modes.
These tools are never installed automatically by holypkg.

## Review, then pack

```sh
holypkg convert sample.pkg.tar.zst --provider artix --stage ./sample-stage
# edit sample-stage/root
holypkg pack ./sample-stage --output ./packages
holypkg collisions ./sample-stage
installpkg ./packages/sample-*.txz
```

`package.json` beside the root tree is staging metadata, not an installed
package database. The package includes provenance and original metadata under
`usr/doc/<name>/holypkg/`. Epoch and release are preserved; unsafe filename
separators are encoded in the Slackware version field.

`--stage` alone chooses a temporary directory and prints its location. Without
`--stage`, conversion runs `makepkg` and leaves the resulting `.txz`. Failed
conversion trees are retained for diagnosis. Existing stage/output paths are
not overwritten.

Artix and Arch are separate providers with separate repositories, mirrors and
trust keyrings. Artix is the preferred donor when preparing our desktop recipe
set. Commands never switch providers or install dependencies:

```sh
holypkg info artix zstd --repo system
holypkg deps arch zstd --repo core
holypkg fetch arch zstd --repo core --keyring /path/to/archlinux.gpg
holypkg artix zstd --repo system --keyring /path/to/artix.gpg --stage
```

Repository metadata is informational until the selected artifact is verified.
Pacman packages require a valid detached signature and the repository SHA-256.
Testing/staging repositories require `--testing`. Multiple matches require a
terminal selection or an explicit repository.

Debian/Ubuntu use signed InRelease metadata and indexed SHA-256/SHA-512 values. Fedora
and openSUSE use RPM metadata and verify the selected RPM with explicitly
provided trust keys. RPM verification uses a disposable key-only store in the
working directory; no foreign package is installed into it.

The RPM backend requires an RPM build with working OpenPGP verification.
The tested Slackware-current RPM 6.1.0 package cannot import the distribution
signing keys; live RPM conversion currently stops rather than skip verification.
A native verification-tool recipe is required before this backend is released.

To select a public key from a downloaded key bundle, verify its full fingerprint
through the provider's published trust information, then run:

```sh
holypkg key add downloaded-keys.asc --fingerprint FULL_FINGERPRINT --keyring provider.asc
```

The command exports only that primary key and its subkeys, refuses to overwrite
an existing file, and does not change your global GnuPG trust. Pass the result
with `--keyring provider.asc`. It does not decide whom you should trust.

```sh
holypkg debian hello --suite sid --keyring /path/to/debian.gpg --stage
holypkg ubuntu hello --suite devel --keyring /path/to/ubuntu.gpg --stage
holypkg fedora hello --keyring /path/to/fedora.asc --stage
holypkg opensuse hello --keyring /path/to/opensuse.asc --stage
```

For a GitHub asset or direct URL, specify the exact artifact, expected checksum,
name, version and installation prefix. `--prefix /` means the archive already
contains a filesystem tree. A prefix such as `/opt/foo` places its entire tree
there. No path stripping or layout guessing is performed.

```sh
holypkg url https://example.org/foo.tar.xz --sha256 EXPECTED_SHA256 \
  --name foo --version 1.0 --prefix /opt/foo --stage
holypkg github owner/project --release v1.0 --asset foo-linux.tar.xz \
  --sha256 EXPECTED_SHA256 --name foo --version 1.0 --prefix /opt/foo --stage
```

## Boundaries

- No dependency resolution, service translation, daemon or compatibility layer.
- No foreign maintainer script execution. Foreign `install/` is quarantined too.
- No package database beyond Slackware's `/var/lib/pkgtools/`.
- Archive traversal, duplicate entries and paths through links are rejected.
- Special files, foreign ownership and extended attributes currently require
  manual handling. Setuid/setgid modes require `--allow-privileged`.
- Existing configuration filenames are preserved; no automatic `.new` rewrite.
- A manually added `install/doinst.sh` is reported when packing. Pkgtools will
  execute it if the user installs that package.
- `--install` requests `doas installpkg` after collision checks. `--force` only
  overrides collisions. It never disables archive-path checks.

`inspect FILE --provider PROVIDER` reports ELF architecture, interpreter,
dynamic dependencies, search paths and version requirements. Host cache misses
are labeled as cache misses, not proof of ABI incompatibility. It never executes
the inspected binary. `scripts` prints preserved foreign maintainer scripts.

## License

New code: Unlicense. Source packages retain their original licenses.
