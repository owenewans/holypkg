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
printf '%s\n' '134c602d8e0d53413a52d6cd58f9ce7e79a07d03288ee0a51ba1abd5db1b1ad9  niri-26.04.tar.gz' | sha256sum -c -
printf '%s\n' '2b467e3336aec63819d6aca28d7310d3dc7415b2b3a3c3a5aec9d3727053c078  libdisplay-info-0.3.0.tar.gz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/libdisplay-info-0.3.0.tar.gz"
# the rust bindings require 0.3; keep it private and link it statically.
meson setup display-build libdisplay-info-0.3.0 --prefix="$WORK/display" --libdir=lib --default-library=static --buildtype=release -Db_staticpic=true
meson compile -C display-build -j "${JOBS:-2}"
meson test -C display-build --print-errorlogs
meson install -C display-build
export PKG_CONFIG_PATH="$WORK/display/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export SYSTEM_DEPS_LIBDISPLAY_INFO_LINK=static
tar xf "$SOURCES/niri-26.04.tar.gz"
cd niri-26.04
export CARGO_TARGET_DIR="$WORK/target"
cargo build --locked --release -p niri --no-default-features --features dbus,xdp-gnome-screencast -j "${JOBS:-2}"
if readelf -d "$CARGO_TARGET_DIR/release/niri" | grep -q 'Shared library: \[libdisplay-info'; then
    echo 'libdisplay-info must be linked statically' >&2
    exit 1
fi
"$CARGO_TARGET_DIR/release/niri" validate --config resources/default-config.kdl
pkg="$WORK/package"
install -Dm755 "$CARGO_TARGET_DIR/release/niri" "$pkg/usr/bin/niri"
strip --strip-unneeded "$pkg/usr/bin/niri"
install -d "$pkg/usr/doc/niri" "$pkg/usr/share/wayland-sessions" "$pkg/install"
cp LICENSE Cargo.lock resources/default-config.kdl "$pkg/usr/doc/niri/"
cp "$WORK/libdisplay-info-0.3.0/LICENSE" "$pkg/usr/doc/niri/libdisplay-info.LICENSE"
printf '%s\n' 'https://github.com/niri-wm/niri/tree/8ed0da44d974c32c6877d2f4630c314da0717ecb' > "$pkg/usr/doc/niri/SOURCE"
# publish the complete dependency sources beside the binary package.
cargo vendor --locked vendor > "$WORK/vendor-config.toml"
mkdir -p .cargo
cp "$WORK/vendor-config.toml" .cargo/config.toml
cp /src/recipes/niri.sh "$WORK/build-niri.sh"
tar -C "$WORK" -cJf "$OUTPUT/niri-26.04-source.tar.xz" niri-26.04 libdisplay-info-0.3.0 build-niri.sh
cat > "$pkg/usr/share/wayland-sessions/niri.desktop" <<'EOF'
[Desktop Entry]
Name=Niri
Comment=Scrollable tiling Wayland compositor
Exec=dbus-run-session -- niri --session
Type=Application
DesktopNames=niri
EOF
cat > "$pkg/install/slack-desc" <<'EOF'
niri: niri (scrollable tiling Wayland compositor)
niri:
niri: Built for Slackware-current with Smithay and the current system libraries.
niri: D-Bus and screencasting support are enabled; systemd integration is off.
niri: The session uses dbus-run-session.
niri:
niri:
niri:
niri:
niri:
niri:
EOF
cd "$pkg"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/niri-26.04-x86_64-1_owen.txz"
