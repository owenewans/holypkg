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
printf '%s\n' '83ba9433282bfe41b4909c4b62ef4c2e757a0ac792c301eccfbb1dd5902b6903  scroll-1.12.21.tar.gz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/scroll-1.12.21.tar.gz"
meson setup build scroll-1.12.21 --prefix=/usr --libdir=lib64 --sysconfdir=/etc --buildtype=release -Dwerror=false --wrap-mode=nodownload -Dauto_features=disabled -Dscrollbar=false -Dscrollnag=true -Ddefault-wallpaper=false -Dzsh-completions=false -Dman-pages=enabled -Dsd-bus-provider=libelogind -Dwlroots:examples=false -Dwlroots:xwayland=enabled -Dwlroots:renderers=gles2 -Dwlroots:backends=drm,libinput -Dwlroots:allocators=gbm -Dwlroots:session=enabled
meson compile -C build -j "${JOBS:-2}"
pkg="$WORK/package"
DESTDIR="$pkg" meson install -C build
install -d "$pkg/usr/doc/scroll" "$pkg/install"
cp scroll-1.12.21/LICENSE "$pkg/usr/doc/scroll/"
cp scroll-1.12.21/subprojects/wlroots/LICENSE "$pkg/usr/doc/scroll/wlroots.LICENSE"
mv "$pkg/etc/scroll/config" "$pkg/usr/doc/scroll/config.example"
rmdir "$pkg/etc/scroll" "$pkg/etc"
strip --strip-unneeded "$pkg/usr/bin/"*
if readelf -d "$pkg/usr/bin/scroll" | grep -q 'NEEDED.*libwlroots'; then
    echo 'unexpected external wlroots dependency' >&2
    exit 1
fi
cat > "$pkg/install/slack-desc" <<'EOF'
scroll: scroll (scrolling Wayland compositor)
scroll:
scroll: Native Slackware build with the upstream private static wlroots fork.
scroll: DRM/libinput, GLES2 and Xwayland; Waybar supplies the panel.
scroll: Configure ~/.config/scroll/config before starting the session.
scroll:
scroll:
scroll:
scroll:
scroll:
scroll:
EOF
cd "$pkg"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/scroll-1.12.21-x86_64-1_owen.txz"
