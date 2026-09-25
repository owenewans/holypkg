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
printf '%s\n' '2aff6468be547b3062ba86b5d04a351ed887e6f0cea3f0f6248e31e58b74c85a  tdlib-ea97bcdd.tar.gz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/tdlib-ea97bcdd.tar.gz"
source=td-ea97bcdd3a15523c58ddfe772b4547187cf5bbeb
cmake -S "$source" -B build -DCMAKE_BUILD_TYPE=Release -DTD_INSTALL_STATIC_LIBRARIES=OFF -DBUILD_TESTING=OFF
cmake --build build --target tdjson -j "${JOBS:-2}"
pkg="$WORK/package"
mkdir -p "$pkg/usr/lib64/telegramtui" "$pkg/usr/doc/telegramtui-tdlib" "$pkg/install"
cp -a build/libtdjson.so* "$pkg/usr/lib64/telegramtui/"
strip --strip-unneeded "$pkg/usr/lib64/telegramtui/"*.so.*
cp "$source/LICENSE_1_0.txt" "$pkg/usr/doc/telegramtui-tdlib/"
printf '%s\n' 'https://github.com/tdlib/td' 'ea97bcdd3a15523c58ddfe772b4547187cf5bbeb' > "$pkg/usr/doc/telegramtui-tdlib/source"
{
    printf '%s\n' 'telegramtui-tdlib: telegramtui-tdlib (native Telegram client library)' 'telegramtui-tdlib:' 'telegramtui-tdlib: Private TDLib JSON library for TelegramTUI on Slackware-current.'
    for line in 1 2 3 4 5 6 7 8; do printf '%s\n' 'telegramtui-tdlib:'; done
} > "$pkg/install/slack-desc"
(cd "$pkg" && TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/telegramtui-tdlib-1.8.67_ea97bcdd-x86_64-1_owen.txz")
