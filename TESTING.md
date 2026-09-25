# Validation ledger

Record actual outcomes here. A compiled provider is not a validated provider.

## Passed on the development host

- Static x86_64-musl executable build with Zig 0.16.0.
- Unit tests for package metadata, pacman database fields and path validation.
- Real tar conversion: provenance, source version, symlinks and script isolation.
- Rejection of traversal, absolute paths, duplicate entries, hardlink escape,
  metadata symlink and provenance-directory symlink.
- Existing staging directories are not overwritten.
- Live Arch core repository lookup for zstd.
- Live signed Arch fetch and Artix system zstd staging.
- Live Debian sid and Ubuntu development hello staging; Ubuntu uses SHA-512.
- Live Fedora Rawhide and openSUSE Tumbleweed package lookup.
- Signed Arch/Artix fixtures: bad signature rejection, explicit key fingerprint,
  separate provider provenance, dependency display, no-clobber fetch.
- PAX ownership retention with explicit `--owner root`, including large UID/GID
  values and unchanged rejection of unsafe archive paths.

## Passed in Slackware-current Podman

Snapshot: official signed package metadata fetched 2026-09-25; glibc 2.44,
libarchive 3.8.9 and RPM 6.1.0. The old bootstrap image was upgraded before tests.

- Adversarial archive fixtures and metadata/script isolation.
- Debian, Ubuntu, Fedora, openSUSE and generic archive format fixtures.
- Rootless makepkg with root-owned archive entries and preserved payload modes.
- installpkg, upgradepkg and removepkg lifecycle, including obsolete-file removal,
  symlinks, configuration permissions and collision detection.

## Native RPM verification

The stock RPM package cannot verify OpenPGP signatures. A private RPM 6.1.0 /
rpm-sequoia 1.10.3 package built on current verifies live Fedora Rawhide and
openSUSE Tumbleweed packages. Both converted hello packages were installed,
executed and removed with pkgtools in a disposable current container. Rawhide
currently signs the tested fc45 package with the Fedora 46 signing key.
Unknown signing keys are rejected; no signature bypass is provided.
Fresh signed RPM fixtures also verify that unsigned packages, unknown keys and
modified payloads are rejected by the native verifier.

## Required before release

- GitHub Actions run 36085844848 passed static build, fixture tests and the five
  Slackware-current test suites. Native verifier CI is being added separately.
- Debian experimental package staging passed for libabsl20260817.
- Exact GitHub asset and URL conversion passed for micro 2.0.15, including
  pkgtools install, executable launch and removal. Add mismatched-checksum tests.
- ELF, filesystem collision and hand-edited staging tests.
- Audit resource limits, PAX attributes, RPM scripts and trust handling.
- Native recipe CI and package repository generation.
