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
printf '%s\n' '21c2bbef88c40473c355003582f9331d2f9b8a01efdcce0935edfc5f6b023a3e  waybar-0.15.0.tar.gz' 'f409856e5920c18d0c2fb85276e24ee607d2a09b5e7d5f0a371368903c275da2  jsoncpp-1.9.5.tar.gz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/waybar-0.15.0.tar.gz"
mkdir -p Waybar-0.15.0/subprojects/packagecache
cp "$SOURCES/jsoncpp-1.9.5.tar.gz" Waybar-0.15.0/subprojects/packagecache/
meson setup build Waybar-0.15.0 --prefix=/usr --libdir=lib64 --buildtype=release --wrap-mode=nodownload -Dauto_features=disabled -Dlibnl=enabled -Dlibudev=enabled -Dwireplumber=enabled -Dniri=true -Dlogin-proxy=false -Djsoncpp:default_library=static -Djsoncpp:tests=false
meson compile -C build -j "${JOBS:-2}"
pkg="$WORK/package"
install -Dm755 build/waybar "$pkg/usr/bin/waybar"
strip --strip-unneeded "$pkg/usr/bin/waybar"
install -d "$pkg/usr/doc/waybar" "$pkg/install"
cp Waybar-0.15.0/LICENSE "$pkg/usr/doc/waybar/"
cp Waybar-0.15.0/subprojects/jsoncpp-1.9.5/LICENSE "$pkg/usr/doc/waybar/jsoncpp.LICENSE"
cat > "$pkg/install/slack-desc" <<'EOF'
waybar: waybar (Wayland status bar)
waybar:
waybar: Native Slackware build with Niri, network, udev and WirePlumber support.
waybar: Optional integrations are disabled; JsonCpp is linked statically.
waybar:
waybar:
waybar:
waybar:
waybar:
waybar:
waybar:
EOF
cd "$pkg"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/waybar-0.15.0-x86_64-1_owen.txz"
