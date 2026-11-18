#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/The Voices.app"
cp -R "build/The Voices.app" "$HOME/Applications/The Voices.app"
echo "Instalada en ~/Applications/The Voices.app"
