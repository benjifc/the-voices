#!/bin/bash
# Genera el instalador "build/The Voices-<versión>.pkg" (instala en /Applications).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP="build/The Voices.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
STAGE="build/pkg-stage"
RESOURCES="$STAGE/resources"
PKG="build/The Voices-$VERSION.pkg"

rm -rf "$STAGE" "$PKG"
mkdir -p "$STAGE/root" "$RESOURCES"
cp -R "$APP" "$STAGE/root/"

# Plist del componente: la app no debe ser reubicable (siempre en /Applications).
pkgbuild --analyze --root "$STAGE/root" "$STAGE/components.plist" >/dev/null
PLISTBUDDY=/usr/libexec/PlistBuddy
$PLISTBUDDY -c 'Add :0:BundleIsRelocatable bool false' "$STAGE/components.plist"
# Reinstalar siempre sustituye la app, aunque la versión no sea más nueva.
$PLISTBUDDY -c 'Set :0:BundleIsVersionChecked false' "$STAGE/components.plist"

pkgbuild \
    --root "$STAGE/root" \
    --component-plist "$STAGE/components.plist" \
    --identifier local.thevoices.app \
    --version "$VERSION" \
    --install-location /Applications \
    "$STAGE/component.pkg" >/dev/null

# Pantallas del instalador (la licencia sale del LICENSE del repositorio).
cp Support/installer/welcome.html Support/installer/conclusion.html "$RESOURCES/"
cp LICENSE "$RESOURCES/license.txt"
sed "s/@VERSION@/$VERSION/" Support/installer/distribution.xml > "$STAGE/distribution.xml"

productbuild \
    --distribution "$STAGE/distribution.xml" \
    --resources "$RESOURCES" \
    --package-path "$STAGE" \
    "$PKG" >/dev/null

rm -rf "$STAGE"
echo "Creado: $PKG"
