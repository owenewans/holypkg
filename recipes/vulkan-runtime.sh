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
printf '%s\n' 'b3203859a9a6b0a08886963492f2795b44629c795b8fa435a366d46676f8f70d  vulkan-sdk-1.4.357.1-x86_64-2.txz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/vulkan-sdk-1.4.357.1-x86_64-2.txz" usr/lib64/libvulkan.so.1.4.357 usr/lib64/libSPIRV-Tools.so usr/lib64/libSPIRV-Tools-opt.so usr/lib64/libSPIRV.so.16.4.0 usr/lib64/libglslang.so.16.4.0 usr/lib64/libglslang-default-resource-limits.so.16.4.0 usr/lib64/libshaderc_shared.so.1 usr/bin/vulkaninfo usr/doc/vulkan-sdk-1.4.357.1
ln -s libvulkan.so.1.4.357 usr/lib64/libvulkan.so.1
ln -s libSPIRV.so.16.4.0 usr/lib64/libSPIRV.so.16
ln -s libglslang.so.16.4.0 usr/lib64/libglslang.so.16
ln -s libglslang-default-resource-limits.so.16.4.0 usr/lib64/libglslang-default-resource-limits.so.16
mkdir -p install
mv usr/doc/vulkan-sdk-1.4.357.1 usr/doc/vulkan-runtime
printf '%s\n' 'Slackware64-current vulkan-sdk-1.4.357.1-x86_64-2.txz' 'SHA256: b3203859a9a6b0a08886963492f2795b44629c795b8fa435a366d46676f8f70d' 'Payload: Vulkan loader, Mesa/libplacebo shader libraries, vulkaninfo, upstream documentation and licenses.' > usr/doc/vulkan-runtime/SOURCE
cat > install/slack-desc <<'EOF'
vulkan-runtime: vulkan-runtime (Vulkan loader and diagnostics)
vulkan-runtime:
vulkan-runtime: Unmodified runtime files from Slackware-current vulkan-sdk.
vulkan-runtime: Mesa/libplacebo shader libraries and vulkaninfo are included.
vulkan-runtime: SDK headers, compiler programs and validation layers are omitted.
vulkan-runtime: Remove this package before installing the full vulkan-sdk package.
vulkan-runtime:
vulkan-runtime:
vulkan-runtime:
vulkan-runtime:
vulkan-runtime:
EOF
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/vulkan-runtime-1.4.357.1-x86_64-1_owen.txz"
