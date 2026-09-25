#!/bin/sh
set -eu
: "${OUTPUT:?output directory}"
: "${WORK:?empty staging directory}"
[ -f /etc/slackware-version ] || exit 1
[ ! -e "$WORK" ] || exit 1
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$OUTPUT" "$WORK"
OUTPUT=$(realpath "$OUTPUT")
WORK=$(realpath "$WORK")
install -Dm755 "$project/zig-out/bin/holypkg" "$WORK/usr/bin/holypkg"
install -d "$WORK/usr/doc/holypkg" "$WORK/install"
cp "$project/LICENSE" "$project/README.md" "$project/TESTING.md" "$WORK/usr/doc/holypkg/"
cat > "$WORK/install/slack-desc" <<'EOF'
holypkg: holypkg (foreign binary package importer)
holypkg:
holypkg: Convert explicitly selected binary packages to Slackware packages.
holypkg: Artix, Arch, Debian, Ubuntu, RPM, GitHub and upstream archives.
holypkg: Dependencies remain the administrator's responsibility.
holypkg:
holypkg:
holypkg:
holypkg:
holypkg:
holypkg:
EOF
cd "$WORK"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/holypkg-0.1.0-x86_64-1_owen.txz"
