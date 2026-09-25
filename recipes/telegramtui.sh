#!/bin/sh
set -eu
: "${SOURCES:?source archive directory}"
: "${OUTPUT:?package output directory}"
: "${WORK:?empty staging directory}"
[ -f /etc/slackware-version ] || exit 1
[ ! -e "$WORK" ] || exit 1
SOURCES=$(realpath "$SOURCES")
mkdir -p "$WORK" "$OUTPUT"
WORK=$(realpath "$WORK")
OUTPUT=$(realpath "$OUTPUT")
cd "$SOURCES"
printf '%s\n' \
  'a65d7f2dc5fb729cf707bed3b5e070983d4d5d8bd6348796ffc84f56c4a2a507  telegramtui-1.0.0.jar' \
  'bfc1ba6a9cdef362229831b6a1cd615b26821a6ff29a2e0e774ac31169dc5ecc  telegramtui-1.0.0.tar.gz' | sha256sum -c -
pkg="$WORK/package"
mkdir -p "$pkg/usr/lib64/telegramtui" "$pkg/usr/bin" "$pkg/usr/doc/telegramtui" "$pkg/install"
install -m644 telegramtui-1.0.0.jar "$pkg/usr/lib64/telegramtui/telegramtui.jar"
tar -xOf telegramtui-1.0.0.tar.gz telegramtui-1.0.0/LICENSE > "$pkg/usr/doc/telegramtui/LICENSE"
cat > "$pkg/usr/bin/telegramtui" <<'EOF'
#!/bin/sh
exec /usr/lib64/telegramtui/jdk-21.0.12.1+1-jre/bin/java -Djna.library.path=/usr/lib64/telegramtui -jar /usr/lib64/telegramtui/telegramtui.jar "$@"
EOF
chmod 755 "$pkg/usr/bin/telegramtui"
printf '%s\n' \
  'Provider: GitHub Releases' \
  'Repository: k4dy/telegramtui' \
  'Release: v1.0.0' \
  'URL: https://github.com/k4dy/telegramtui/releases/download/v1.0.0/telegramtui-1.0.0.jar' \
  'SHA256: a65d7f2dc5fb729cf707bed3b5e070983d4d5d8bd6348796ffc84f56c4a2a507' \
  'Runtime: Temurin 21.0.12.1 and native TDLib 1.8.67 (separate packages)' > "$pkg/usr/doc/telegramtui/provenance"
{
    printf '%s\n' 'telegramtui: telegramtui (terminal Telegram client)' 'telegramtui:' 'telegramtui: Unmodified upstream JAR with an explicit Slackware launcher.'
    for line in 1 2 3 4 5 6 7 8; do printf '%s\n' 'telegramtui:'; done
} > "$pkg/install/slack-desc"
(cd "$pkg" && TAR_OPTIONS='--owner=0 --group=0 --numeric-owner' makepkg -l n -c n "$OUTPUT/telegramtui-1.0.0-noarch-1_holygh.txz")
