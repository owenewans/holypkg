#!/bin/sh
set -eu
: "${SOURCES:?directory containing pinned source archives}"
: "${OUTPUT:?package output directory}"
: "${WORK:?empty disposable build directory}"
[ -f /etc/slackware-version ] || { echo 'build inside Slackware-current' >&2; exit 1; }
[ ! -e "$WORK" ] || { echo 'WORK must not exist' >&2; exit 1; }
mkdir -p "$WORK" "$OUTPUT"
SOURCES=$(realpath "$SOURCES")
OUTPUT=$(realpath "$OUTPUT")
WORK=$(realpath "$WORK")
export LC_ALL=C
cd "$SOURCES"
printf '%s\n' \
 'f520810d27c74bf1c5d8b8885845c61e0c845f62d33e68b02e020633a8b62fe3  rpm-6.1.0.tar.bz2' \
 '493f904c3f776839929a329028ba1b227d5d86ec5bd6158f9d25542981545bfe  rpm-sequoia-1.10.3.tar.gz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/rpm-6.1.0.tar.bz2"
tar xf "$SOURCES/rpm-sequoia-1.10.3.tar.gz"
prefix=/usr/libexec/holypkg-rpm
seq="$WORK/rpm-sequoia-8e0b76e1e75c83d7d8e6f38976b0c83b52ebe7ee"
cd "$seq"
PREFIX="$prefix" LIBDIR="$prefix/lib64" cargo build --locked --release --no-default-features --features crypto-openssl
target=${CARGO_TARGET_DIR:-$seq/target}
install -d "$prefix/lib64/pkgconfig"
install -m755 "$target/release/librpm_sequoia.so" "$prefix/lib64/"
ln -sfn librpm_sequoia.so "$prefix/lib64/librpm_sequoia.so.1"
install -m644 "$target/release/rpm-sequoia.pc" "$prefix/lib64/pkgconfig/"
export PKG_CONFIG_PATH="$prefix/lib64/pkgconfig"
cmake -S "$WORK/rpm-6.1.0" -B "$WORK/rpm-build" -G Ninja \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib64 \
 -DCMAKE_INSTALL_RPATH="$prefix/lib64" -DCMAKE_BUILD_RPATH="$prefix/lib64" \
 -DENABLE_PYTHON=OFF -DENABLE_PLUGINS=OFF -DENABLE_NLS=OFF -DENABLE_OPENMP=OFF \
 -DENABLE_TESTSUITE=OFF -DWITH_AUDIT=OFF -DWITH_SELINUX=OFF -DWITH_DBUS=OFF \
 -DWITH_SEQUOIA=ON -DWITH_OPENSSL=ON -DWITH_FAPOLICYD=OFF
cmake --build "$WORK/rpm-build" -j "${JOBS:-4}"
pkg="$WORK/package"
DESTDIR="$pkg" cmake --install "$WORK/rpm-build"
install -m755 "$prefix/lib64/librpm_sequoia.so" "$pkg$prefix/lib64/"
ln -s librpm_sequoia.so "$pkg$prefix/lib64/librpm_sequoia.so.1"
# only verification is exposed; pkgtools remains the installed-package database.
find "$pkg$prefix/bin" -type f ! -name rpmkeys -delete
rm -rf "$pkg$prefix/include" "$pkg$prefix/lib64/pkgconfig" "$pkg$prefix/share/man"
install -d "$pkg/usr/doc/holypkg-rpm-tools" "$pkg/install"
cp "$WORK/rpm-6.1.0/COPYING" "$pkg/usr/doc/holypkg-rpm-tools/COPYING.rpm"
cp "$seq/LICENSE.txt" "$pkg/usr/doc/holypkg-rpm-tools/COPYING.rpm-sequoia"
cat > "$pkg/usr/doc/holypkg-rpm-tools/SOURCES" <<'EOF'
RPM 6.1.0: https://github.com/rpm-software-management/rpm/releases/tag/rpm-6.1.0-release
rpm-sequoia 1.10.3: https://github.com/rpm-software-management/rpm-sequoia/tree/8e0b76e1e75c83d7d8e6f38976b0c83b52ebe7ee
Recipe and source checksums: https://github.com/owenewans/holypkg/blob/main/recipes/rpm-tools.sh
EOF
cat > "$pkg/install/slack-desc" <<'EOF'
holypkg-rpm-tools: holypkg-rpm-tools (native RPM signature verification)
holypkg-rpm-tools:
holypkg-rpm-tools: Private RPM tools with Sequoia OpenPGP support.
holypkg-rpm-tools: Built for Slackware-current; does not replace system rpm.
holypkg-rpm-tools: Used only for foreign binary signature verification.
holypkg-rpm-tools:
holypkg-rpm-tools:
holypkg-rpm-tools:
holypkg-rpm-tools:
holypkg-rpm-tools:
holypkg-rpm-tools:
EOF
cd "$pkg"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/holypkg-rpm-tools-6.1.0-x86_64-1_owen.txz"
