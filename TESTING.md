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

## Passed in Slackware-current Podman

Snapshot: official signed package metadata fetched 2026-09-25; glibc 2.44,
libarchive 3.8.9 and RPM 6.1.0. The old bootstrap image was upgraded before tests.

- Adversarial archive fixtures and metadata/script isolation.
- Debian, Ubuntu, Fedora, openSUSE and generic archive format fixtures.
- Rootless makepkg with root-owned archive entries and preserved payload modes.
- installpkg, upgradepkg and removepkg lifecycle, including obsolete-file removal,
  symlinks, configuration permissions and collision detection.

## Known failure

Live Fedora/openSUSE signature checks stop at key import with the current native
RPM package. GnuPG reads both published keys; rpmkeys rejects them. The upstream
SlackBuild disables Sequoia and RPM 6.1's dummy OpenPGP backend cannot import keys.
No verification bypass is provided. Build and test a native verification helper.

## Required before release

- Reproducible Slackware-current CI integration.
- Debian experimental repository tests.
- Fedora Rawhide and openSUSE Tumbleweed metadata and RPM signature tests.
- Exact GitHub asset and URL conversion tests with mismatched checksums.
- ELF, filesystem collision and hand-edited staging tests.
- Audit resource limits, PAX attributes, RPM scripts and trust handling.
- Native recipe CI and package repository generation.
