#!/bin/sh
set -eu
: "${SOURCES:?verified Slackware package directory}"
: "${OUTPUT:?output directory}"
: "${WORK:?empty build directory}"
[ -f /etc/slackware-version ] || exit 1
[ ! -e "$WORK" ] || exit 1
SOURCES=$(realpath "$SOURCES")
mkdir -p "$WORK" "$OUTPUT"
WORK=$(realpath "$WORK")
OUTPUT=$(realpath "$OUTPUT")
cd "$SOURCES"
printf '%s\n' '4c8f8b872a5a6587e3b368a51c46f157ef2c5a080a62855ea05d75730461cfd1  llvm-23.1.2-x86_64-1.txz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/llvm-23.1.2-x86_64-1.txz" usr/lib64/libLLVM.so.23.1 usr/doc/llvm-23.1.2/LICENSE.TXT
mkdir -p install usr/doc/llvm-runtime
mv usr/doc/llvm-23.1.2/LICENSE.TXT usr/doc/llvm-runtime/
rmdir usr/doc/llvm-23.1.2
printf '%s\n' 'Slackware64-current llvm-23.1.2-x86_64-1.txz' 'SHA256: 4c8f8b872a5a6587e3b368a51c46f157ef2c5a080a62855ea05d75730461cfd1' 'Payload: usr/lib64/libLLVM.so.23.1 and LICENSE.TXT only.' > usr/doc/llvm-runtime/SOURCE
cat > install/slack-desc <<'EOF'
llvm-runtime: llvm-runtime (LLVM shared library for Mesa)
llvm-runtime:
llvm-runtime: The unmodified LLVM shared library from Slackware-current.
llvm-runtime: Compiler programs, development headers and static libraries are omitted.
llvm-runtime: Installing the full llvm package overlaps this package; remove this
llvm-runtime: runtime package before installing the full development package.
llvm-runtime:
llvm-runtime:
llvm-runtime:
llvm-runtime:
llvm-runtime:
EOF
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/llvm-runtime-23.1.2-x86_64-1_owen.txz"
