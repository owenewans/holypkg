<div align="center">

# holypkg

foreign binary packages to native slackware packages.

<a href="https://count.owenewans.org/owenewans/holypkg?theme=moebooru-h&notitle"><img src="https://count.owenewans.org/owenewans/holypkg?theme=moebooru-h&notitle" alt="repository views"></a>

`zig` `packages` `slackware`

</div>

## features

- Artix and Arch providers with separate repositories, mirrors and keyrings
- Debian sid/experimental, Ubuntu development, Fedora Rawhide and openSUSE
  Tumbleweed packages
- GitHub release assets and upstream archives with an explicit checksum and layout
- editable staging trees, source metadata and provenance inside each package
- ELF diagnostics, foreign script inspection and filesystem collision checks
- native Slackware build recipes under [`recipes`](recipes)

Development is in progress. See [validation and remaining coverage](TESTING.md).

## build

Requires Zig 0.16.0:

```sh
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
zig build test
python3 tests/archive.py zig-out/bin/holypkg
```

The static executable is `zig-out/bin/holypkg`. Runtime tools come from
Slackware: `curl`, `bsdtar`, compression tools, GnuPG, coreutils, `find` and
`makepkg`. RPM input also requires `rpm` and `rpm2cpio`; ELF inspection uses
`readelf`. Install these tools yourself.

## usage

```sh
holypkg info artix zstd --repo system
holypkg deps arch zstd --repo core
holypkg fetch arch zstd --repo core --keyring /path/to/archlinux.gpg
holypkg artix zstd --repo system --keyring /path/to/artix.gpg --stage ./zstd-stage
```

Select the provider yourself. Artix is the preferred donor for our workstation
recipes; holypkg does not switch sources or resolve dependencies. Enable
non-stable pacman repositories with `--testing`. Multiple matches prompt for
selection; use `--repo` to select a repository in advance.

Convert a local package, edit its tree, then pack and install it:

```sh
holypkg convert sample.pkg.tar.zst --provider artix --stage ./sample-stage
# edit sample-stage/root
holypkg pack ./sample-stage --output ./packages
holypkg collisions ./sample-stage
installpkg ./packages/sample-*.txz
```

`--stage` without a path creates a temporary directory and prints its location.
Omit `--stage` to create the `.txz` in one step. Existing output paths are
preserved. Failed staging trees remain available for inspection.

Use the same provider commands for the other distribution repositories:

```sh
holypkg debian hello --suite sid --keyring /path/to/debian.gpg --stage
holypkg ubuntu hello --suite devel --keyring /path/to/ubuntu.gpg --stage
holypkg fedora hello --keyring /path/to/fedora.asc --stage
holypkg opensuse hello --keyring /path/to/opensuse.asc --stage
```

For upstream archives, supply the name, version, checksum and prefix:

```sh
holypkg github owner/project --release v1.0 --asset foo-linux.tar.xz \
  --sha256 EXPECTED_SHA256 --name foo --version 1.0 --prefix /opt/foo --stage
holypkg url https://example.org/foo.tar.xz --sha256 EXPECTED_SHA256 \
  --name foo --version 1.0 --prefix /opt/foo --stage
```

`--prefix /` keeps an existing filesystem layout. `/opt/foo` places the entire
archive tree there, without stripping directories or guessing paths.

## trust

Pacman imports require the repository SHA-256 and a valid package signature.
Debian and Ubuntu imports verify signed InRelease metadata and indexed
SHA-256/SHA-512 checksums. Fedora and openSUSE imports verify the selected RPM
with the supplied keys. Local `convert` records the source as unverified.

Check a key's full fingerprint against the provider's published information,
then export it from a downloaded bundle:

```sh
holypkg key add downloaded-keys.asc --fingerprint FULL_FINGERPRINT --keyring provider.asc
```

Pass the result with `--keyring provider.asc`. The command exports the selected
primary key and its subkeys, preserves existing files and leaves global GnuPG
trust untouched.

Slackware-current's RPM 6.1.0 lacks OpenPGP verification. The
[`holypkg-rpm-tools` recipe](recipes/rpm-tools.sh) builds a private Sequoia-backed
verifier at `/usr/libexec/holypkg-rpm/bin/rpmkeys`. Repository imports verify
signatures before querying metadata. The temporary RPM key store contains
trust keys only; system RPM remains in place.

## package rules

Slackware pkgtools manages installed packages in `/var/lib/pkgtools/`.
Staging `package.json` describes the work tree. Installed provenance, original
metadata and foreign scripts live under `/usr/doc/<name>/holypkg/`. Epoch and
package release remain distinguishable in encoded Slackware version names.

Foreign maintainer scripts and service definitions are not executed or
translated. Configuration filenames remain unchanged. If you add
`install/doinst.sh` yourself, packing reports it and pkgtools executes it at
installation.

Archive traversal, duplicate entries, paths through links and special files
are rejected. Extended attributes and RPM capabilities require manual handling.
Use `--owner root` to map foreign ownership to root, retaining original UID/GID
values in `source-files.json`. Setuid/setgid modes require `--allow-privileged`.
Rootless packaging preserves modes and sets root ownership in tar headers.

`inspect FILE --provider PROVIDER` reports ELF architecture, interpreter,
libraries, search paths and symbol versions without executing the binary.
Missing host cache entries do not establish ABI incompatibility. `scripts`
prints the preserved maintainer scripts.

`--install` calls `doas installpkg` after collision checks. `--force` overrides
collisions only; archive path checks still apply. Update or remove packages
with `upgradepkg` and `removepkg`.

## license

[Unlicense](LICENSE). Upstream packages retain their own licenses.
