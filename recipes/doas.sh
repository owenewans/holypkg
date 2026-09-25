#!/bin/sh
set -eu
: "${SOURCES:?source archive directory}"
: "${OUTPUT:?package output directory}"
: "${WORK:?empty disposable build directory}"
[ -f /etc/slackware-version ] || exit 1
[ ! -e "$WORK" ] || { echo 'WORK must not exist' >&2; exit 1; }
recipe=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCES=$(realpath "$SOURCES")
mkdir -p "$WORK" "$OUTPUT"
WORK=$(realpath "$WORK")
OUTPUT=$(realpath "$OUTPUT")
cd "$SOURCES"
printf '%s\n' 'a01138f91d22a8ccbf7a301a854dedc1a00aea7ef644f657f1f07134a56d2f3e  opendoas-b96106b.tar.gz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/opendoas-b96106b.tar.gz"
cd OpenDoas-b96106b7e34ac591ae78b1684e9be3a265122463
patch -p1 < "$recipe/doas-persist.patch"
./configure --prefix=/usr --sysconfdir=/etc --mandir=/usr/man --with-pam --with-timestamp
make -j "${JOBS:-4}"
pkg="$WORK/package"
make DESTDIR="$pkg" install
install -d "$pkg/etc/pam.d" "$pkg/usr/doc/owendoas" "$pkg/install"
cp LICENSE "$pkg/usr/doc/owendoas/"
cp "$recipe/doas-persist.patch" "$pkg/usr/doc/owendoas/"
cat > "$pkg/etc/pam.d/doas.new" <<'EOF'
#%PAM-1.0
auth include system-auth
account include system-auth
session include system-auth
EOF
printf '300\n' > "$pkg/etc/doas-persist.conf.new"
cat > "$pkg/usr/doc/owendoas/README" <<'EOF'
OpenDoas source: https://github.com/Duncaen/OpenDoas/tree/b96106b7e34ac591ae78b1684e9be3a265122463
The included patch reads /etc/doas-persist.conf as a decimal number of seconds.
Range: 0..86400. Zero disables timestamp reuse. Missing file: 300 seconds.
The file must be a regular root-owned file without group/other write permission.
Symlinks, malformed content and unsafe ownership or permissions cause refusal.
Use 'permit persist :wheel' in /etc/doas.conf to enable caching for wheel.
This package does not create an authorization policy. The installer writes it.
EOF
cat > "$pkg/install/doinst.sh" <<'EOF'
config() {
  new=$1
  old=${new%.new}
  if [ ! -e "$old" ]; then
    mv "$new" "$old"
  elif cmp -s "$new" "$old"; then
    rm "$new"
  fi
}
config etc/pam.d/doas.new
config etc/doas-persist.conf.new
EOF
cat > "$pkg/install/slack-desc" <<'EOF'
owendoas: owendoas (OpenDoas with configurable password persistence)
owendoas:
owendoas: Native Slackware-current OpenDoas build with PAM authentication.
owendoas: Root configures the timestamp duration in doas-persist.conf.
owendoas: The upstream authorization model and timestamp checks are retained.
owendoas:
owendoas:
owendoas:
owendoas:
owendoas:
owendoas:
EOF
cd "$pkg"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/owendoas-6.8.2_b96106b-x86_64-1_owen.txz"
