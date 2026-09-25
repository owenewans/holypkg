#!/bin/sh
set -eu
: "${SOURCES:?source archive directory}"
: "${OUTPUT:?package output directory}"
: "${WORK:?empty disposable build directory}"
[ -f /etc/slackware-version ] || exit 1
[ ! -e "$WORK" ] || exit 1
SOURCES=$(realpath "$SOURCES")
mkdir -p "$WORK" "$OUTPUT"
WORK=$(realpath "$WORK")
OUTPUT=$(realpath "$OUTPUT")
cd "$SOURCES"
printf '%s\n' '9a738586bff5790bd8bfef4a4868a2939cba3f81f22f121306d668c97f1c85d8  limine-binary-12.9.0.tar.xz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/limine-binary-12.9.0.tar.xz"
cd limine-binary
make CFLAGS='-O2 -pipe'
pkg="$WORK/package"
install -Dm755 limine "$pkg/usr/bin/limine"
install -d "$pkg/usr/share/limine" "$pkg/usr/doc/limine" "$pkg/install"
for file in BOOTX64.EFI limine-bios.sys limine-bios-cd.bin limine-uefi-cd.bin; do
  install -m644 "$file" "$pkg/usr/share/limine/$file"
done
cp LICENSE "$pkg/usr/doc/limine/"
printf '%s\n' 'https://github.com/Limine-Bootloader/Limine/releases/tag/v12.9.0' > "$pkg/usr/doc/limine/SOURCE"
cat > "$pkg/install/slack-desc" <<'EOF'
limine: limine (BIOS and UEFI bootloader)
limine:
limine: Limine 12.9.0 x86_64 EFI and BIOS boot assets.
limine: The bios-install utility is built on Slackware-current.
limine: Kernels and initramfs must be stored on a supported FAT filesystem.
limine:
limine:
limine:
limine:
limine:
limine:
EOF
cd "$pkg"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/limine-12.9.0-x86_64-1_owen.txz"
