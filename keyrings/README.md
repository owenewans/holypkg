# provider keyrings

Public verification keys shipped with the Slackware package. No private keys.
`--keyring FILE` overrides the installed provider keyring. Import additional
reviewed keys with `holypkg key add`; holypkg does not fetch unknown signers.

| file | upstream package | SHA-256 |
| --- | --- | --- |
| arch.gpg | archlinux-keyring 20260902-1, installed Arch package | 630169e9414635f8a41dbe82d0758c35571eee4340994559e0e7d246599bb27f |
| artix.gpg | artix-keyring 20250105-1, usr/share/pacman/keyrings/artix.gpg | e934c6e4105b79552e45e3358e272fd9f99230aa753f02c5318d20804c659720 |

Sources: [Arch keyring](https://gitlab.archlinux.org/archlinux/archlinux-keyring),
[Artix keyring package](https://mirror1.artixlinux.org/repos/system/os/x86_64/artix-keyring-20250105-1-any.pkg.tar.zst).
The Artix source archive SHA-256 is
`c6d467c7cecafd64465859feacc23118529663aa6a1c60e843e1a9c42660d0e8`.

Refresh these snapshots from their upstream keyring packages when maintainers
rotate or revoke keys. Local extra keys belong in a separate keyring selected
with `--keyring`, so package upgrades do not replace local trust decisions.
