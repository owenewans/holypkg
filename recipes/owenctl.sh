#!/bin/sh
set -eu
: "${SOURCES:?source archive directory}"
: "${OWENDOTS:?owendots source checkout}"
: "${OUTPUT:?package output directory}"
: "${WORK:?empty build directory}"
[ -f /etc/slackware-version ] || exit 1
[ ! -e "$WORK" ] || exit 1
SOURCES=$(realpath "$SOURCES")
OWENDOTS=$(realpath "$OWENDOTS")
mkdir -p "$WORK" "$OUTPUT"
WORK=$(realpath "$WORK")
OUTPUT=$(realpath "$OUTPUT")
cd "$SOURCES"
printf '%s\n' \
  '2b3ee1e2120c7a0796b33062c7e9a694dd8a8caa56a96319ac8c8ecf54a90d0b  raylib-6.0.tar.gz' \
  '0f194c4a5e837c0930aca0b6315db45d00f76fa0052d841eea94598d390c39d6  raygui-5.0.tar.gz' \
  '70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00  zig-x86_64-linux-0.16.0.tar.xz' | sha256sum -c -
cd "$WORK"
tar xf "$SOURCES/raylib-6.0.tar.gz"
tar xf "$SOURCES/raygui-5.0.tar.gz"
tar xf "$SOURCES/zig-x86_64-linux-0.16.0.tar.xz"
cmake -S raylib-6.0 -B raylib-build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$WORK/prefix" -DCMAKE_INSTALL_LIBDIR=lib -DPLATFORM=SDL -DBUILD_EXAMPLES=OFF -DCUSTOMIZE_BUILD=ON -DUSE_AUDIO=OFF -DSUPPORT_MODULE_RMODELS=OFF -DSUPPORT_MODULE_RAUDIO=OFF -DSUPPORT_CUSTOM_FRAME_CONTROL=OFF -DSUPPORT_BUSY_WAIT_LOOP=OFF -DSUPPORT_PARTIALBUSY_WAIT_LOOP=OFF -DSUPPORT_SCREEN_CAPTURE=OFF -DSUPPORT_AUTOMATION_EVENTS=OFF -DSUPPORT_SSH_KEYBOARD_RPI=OFF
cmake --build raylib-build -j "${JOBS:-2}"
cmake --install raylib-build
cp raygui-5.0/src/raygui.h prefix/include/
mkdir project
cp "$OWENDOTS/build.zig" project/
cp -R "$OWENDOTS/src" project/
cd project
"$WORK/zig-x86_64-linux-0.16.0/zig" build gui -Dgui-deps="$WORK/prefix" -Doptimize=ReleaseSafe -Dcpu=baseline
pkg="$WORK/package"
install -Dm755 zig-out/bin/owenctl "$pkg/usr/bin/owenctl"
install -d "$pkg/usr/doc/owenctl" "$pkg/install"
cp "$OWENDOTS/LICENSE" "$pkg/usr/doc/owenctl/"
cp "$WORK/raylib-6.0/LICENSE" "$pkg/usr/doc/owenctl/raylib.LICENSE"
cp "$WORK/raygui-5.0/LICENSE" "$pkg/usr/doc/owenctl/raygui.LICENSE"
cp "$WORK/zig-x86_64-linux-0.16.0/LICENSE" "$pkg/usr/doc/owenctl/zig.LICENSE"
cat > "$pkg/install/slack-desc" <<'EOF'
owenctl: owenctl (owendots desktop controls)
owenctl:
owenctl: Zig and Raygui controls with a shared application palette.
owenctl: Native Slackware build with Raylib and the SDL3 Wayland backend.
owenctl:
owenctl:
owenctl:
owenctl:
owenctl:
owenctl:
owenctl:
EOF
cd "$pkg"
TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/owenctl-0.1.0-x86_64-1_owen.txz"
