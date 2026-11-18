#!/bin/bash
# Publica una versión de The Voices.
#
#   scripts/release.sh X.Y.Z [--dry-run] [--draft] [--yes]
#
# 1. Comprueba rama, árbol limpio y versión nueva (SemVer, mayor que la última etiqueta).
# 2. Pasa a «X.Y.Z» la sección «Sin publicar» de CHANGELOG.md y sube CFBundleVersion.
# 3. Ejecuta los tests, compila la app y genera TheVoices-X.Y.Z.pkg y TheVoices-X.Y.Z.zip.
# 4. Firma el .zip con la clave EdDSA de Sparkle (llavero) y genera appcast.xml.
# 5. Tras confirmar: commit «chore(release)», etiqueta vX.Y.Z, push y release de GitHub con
#    el .pkg, el .zip y el appcast.xml. Las apps instaladas se actualizan solas desde ahí.
#
# --dry-run  hace los pasos 1-4 y deja los ficheros en build/, sin tocar git ni GitHub
#            (CHANGELOG.md e Info.plist se restauran al terminar).
# --draft    crea la release como borrador (no es «latest» hasta publicarla en GitHub).
# --yes      no pide confirmación.
#
# Variables: SKIP_TESTS=1 omite los tests · ALLOW_ANY_BRANCH=1 permite publicar desde una
# rama distinta de main · RELEASE_GH_USER (por defecto benjifc) cuenta de gh usada.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="benjifc/the-voices"
GH_USER="${RELEASE_GH_USER:-benjifc}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
PLIST="Support/Info.plist"
PB=/usr/libexec/PlistBuddy

VERSION="${1:-}"
[ -n "$VERSION" ] || { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
shift
DRY=0 DRAFT=0 YES=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --draft) DRAFT=1 ;;
        --yes) YES=1 ;;
        *) echo "Opción desconocida: $arg" >&2; exit 1 ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "versión no válida «$VERSION» (se espera X.Y.Z)"
TAG="v$VERSION"

# --- 1. Comprobaciones -------------------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ] && [ "${ALLOW_ANY_BRANCH:-0}" != 1 ]; then
    die "estás en «$BRANCH»; publica desde main (o usa ALLOW_ANY_BRANCH=1)"
fi
[ -z "$(git status --porcelain -- . ':!build')" ] || die "hay cambios sin commitear; commitea o descarta antes de publicar"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "la etiqueta $TAG ya existe"
LAST_TAG="$(git tag --list 'v[0-9]*' | sed 's/^v//' | sort -V | tail -1)"
if [ -n "$LAST_TAG" ]; then
    NEWEST="$(printf '%s\n%s\n' "$LAST_TAG" "$VERSION" | sort -V | tail -1)"
    [ "$NEWEST" = "$VERSION" ] || die "$VERSION no es mayor que la última versión publicada ($LAST_TAG)"
fi
if [ "$DRY" = 0 ]; then
    command -v gh >/dev/null || die "falta gh (GitHub CLI)"
    export GH_TOKEN="$(gh auth token --user "$GH_USER")" || die "gh no tiene la cuenta $GH_USER"
fi
[ -x "$SPARKLE_BIN/sign_update" ] || swift package resolve >/dev/null
[ -x "$SPARKLE_BIN/sign_update" ] || die "no encuentro $SPARKLE_BIN/sign_update (¿compilaste el proyecto?)"

# --- 2. Versión y changelog ----------------------------------------------------------------
RESTORE=0
trap '[ "$RESTORE" = 1 ] && git checkout -- "$PLIST" CHANGELOG.md || true' EXIT
BUILD=$(( $("$PB" -c 'Print :CFBundleVersion' "$PLIST") + 1 ))
RESTORE=1
python3 scripts/release_tools.py promote "$VERSION" "$(date +%Y-%m-%d)"
"$PB" -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
"$PB" -c "Set :CFBundleVersion $BUILD" "$PLIST"
mkdir -p build
python3 scripts/release_tools.py notes "$VERSION" > build/release-notes.md

# --- 3. Tests y artefactos -----------------------------------------------------------------
if [ "${SKIP_TESTS:-0}" != 1 ]; then
    swift test 2>&1 | tail -3
fi
./scripts/build-pkg.sh
PKG="build/TheVoices-$VERSION.pkg"
ZIP="build/TheVoices-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/The Voices.app" "$ZIP"

# --- 4. Firma y appcast --------------------------------------------------------------------
SIGN_OUT="$("$SPARKLE_BIN/sign_update" "$ZIP")"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGN_OUT")"
LENGTH="$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<<"$SIGN_OUT")"
[ -n "$SIGNATURE" ] && [ -n "$LENGTH" ] || die "sign_update no devolvió firma: $SIGN_OUT"
python3 scripts/release_tools.py appcast "$VERSION" "$BUILD" \
    "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')" \
    "https://github.com/$REPO/releases/download/$TAG/TheVoices-$VERSION.zip" \
    "$SIGNATURE" "$LENGTH" > build/appcast.xml
xmllint --noout build/appcast.xml

echo
echo "Versión $VERSION (build $BUILD)"
echo "  $PKG"
echo "  $ZIP"
echo "  build/appcast.xml"
echo "  build/release-notes.md"

if [ "$DRY" = 1 ]; then
    echo "Simulacro terminado: no se ha tocado git ni GitHub (CHANGELOG.md e Info.plist restaurados)."
    exit 0
fi

# --- 5. Publicación ------------------------------------------------------------------------
if [ "$YES" != 1 ]; then
    echo
    echo "Se va a: commitear, crear la etiqueta $TAG, hacer push a origin/$BRANCH y publicar la"
    echo "release en https://github.com/$REPO (visible públicamente)."
    read -r -p "¿Continuar? [s/N] " answer
    [[ "$answer" =~ ^[sSyY]$ ]] || die "cancelado (CHANGELOG.md e Info.plist se restauran)"
fi

git add "$PLIST" CHANGELOG.md
git commit -q -m "chore(release): $TAG

Benjamin Fernandez Carrasco"
RESTORE=0
git tag -a "$TAG" -m "The Voices $VERSION"

# Comprobación de autoría antes de subir nada (el patrón va partido para que este mismo
# fichero no lo contenga).
AI_PATTERN='cla''ude|anthro''pic'
if git grep -niE "$AI_PATTERN" >/dev/null || \
   git log --format='%an%n%ae%n%B' | grep -qiE "$AI_PATTERN|co-authored-by"; then
    die "hay menciones a herramientas de IA en el repositorio; no se sube nada"
fi

git push origin "$BRANCH" "$TAG"
ARGS=(--title "The Voices $VERSION" --notes-file build/release-notes.md --verify-tag)
[ "$DRAFT" = 1 ] && ARGS+=(--draft)
gh release create "$TAG" "$PKG" "$ZIP" build/appcast.xml --repo "$REPO" "${ARGS[@]}"
echo "Publicada: https://github.com/$REPO/releases/tag/$TAG"
