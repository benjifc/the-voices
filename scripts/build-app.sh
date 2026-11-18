#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/The Voices.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TheVoices" "$APP/Contents/MacOS/TheVoices"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Recursos de dependencias (p. ej. KeyboardShortcuts)
for b in "$BIN_DIR"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

codesign --force --deep --sign - "$APP"
echo "Creada: $APP"
