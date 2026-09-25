#!/bin/sh
set -eu
: "${SOURCES:?source archive directory}"
: "${OUTPUT:?package output directory}"
: "${WORK:?empty build directory}"
[ -f /etc/slackware-version ] || exit 1
[ ! -e "$WORK" ] || exit 1
SOURCES=$(realpath "$SOURCES")
mkdir -p "$WORK" "$OUTPUT"
WORK=$(realpath "$WORK")
OUTPUT=$(realpath "$OUTPUT")
cd "$SOURCES"
printf '%s\n' \
  '60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b  aria2-1.37.0.tar.xz' \
  '9e72a98f7621b1f5741b405b8dbd447acf7d300ddb12667ec526db1ce6154eaa  grim-1.5.0.tar.gz' \
  '0f70cbc665217a747e8a098e1a881239e96df270930f47c262ab2ecff290e428  swayimg-5.6.tar.gz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/aria2-1.37.0.tar.xz"
tar xf "$SOURCES/grim-1.5.0.tar.gz"
tar xf "$SOURCES/swayimg-5.6.tar.gz"
cd aria2-1.37.0
./configure --prefix=/usr --libdir=/usr/lib64 --docdir=/usr/doc/aria2 --disable-nls --without-gnutls --without-libnettle --with-openssl --with-libcares --with-libssh2
make -j "${JOBS:-2}"
make DESTDIR="$WORK/aria2-package" install
install -Dm644 COPYING "$WORK/aria2-package/usr/doc/aria2/COPYING"
cd "$WORK"
meson setup grim-build grim-v1.5.0 --prefix=/usr --libdir=lib64 --buildtype=release --wrap-mode=nodownload -Djpeg=disabled -Dman-pages=enabled
meson compile -C grim-build -j "${JOBS:-2}"
DESTDIR="$WORK/grim-package" meson install -C grim-build
install -Dm644 grim-v1.5.0/LICENSE "$WORK/grim-package/usr/doc/grim/LICENSE"
meson setup swayimg-build swayimg-5.6 --prefix=/usr --libdir=lib64 --buildtype=release --wrap-mode=nodownload -Dauto_features=disabled -Dliblua=lua -Dwayland=enabled -Dpng=enabled -Djpeg=enabled -Dwebp=enabled -Dgif=enabled -Dsvg=enabled -Dtiff=enabled -Djxl=enabled -Dlicense=false
meson compile -C swayimg-build -j "${JOBS:-2}"
DESTDIR="$WORK/swayimg-package" meson install -C swayimg-build
install -Dm644 swayimg-5.6/LICENSE "$WORK/swayimg-package/usr/doc/swayimg/LICENSE"
for spec in aria2:1.37.0 grim:1.5.0 swayimg:5.6; do
    name=${spec%:*}
    version=${spec#*:}
    pkg="$WORK/$name-package"
    strip --strip-unneeded "$pkg/usr/bin/"*
    mkdir -p "$pkg/install"
    {
        printf '%s\n' "$name: $name (native workstation utility)" "$name:" "$name: Built from pinned upstream sources for Slackware64-current."
        for line in 1 2 3 4 5 6 7 8; do printf '%s:\n' "$name"; done
    } > "$pkg/install/slack-desc"
    (cd "$pkg" && TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/$name-$version-x86_64-1_owen.txz")
done
