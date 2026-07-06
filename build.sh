#!/bin/zsh
# Construit Conso Claude.app — binaire universel (Apple Silicon + Intel),
# phrases.json + icône embarqués, signature ad-hoc.
# Le bundle est assemblé de zéro à chaque build (staging) : évite les attributs
# Finder (com.apple.FinderInfo) qui font échouer codesign sur un bundle réutilisé.
#
#   ./build.sh             build seulement
#   ./build.sh --install   build + installe dans /Applications + relance
#   ./build.sh --zip       build + crée "Conso Claude.zip" à partager
#
set -e
cd "$(dirname "$0")"
APP="Conso Claude.app"
# Staging dans un tmpdir système : les fichiers créés sous ~/Documents reçoivent
# com.apple.provenance, que codesign refuse (« detritus »). Pas en /tmp.
BUILD="$(mktemp -d /tmp/conso-claude-build.XXXXXX)"
trap 'rm -rf "$BUILD"' EXIT
STAGE="$BUILD/$APP"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

echo "→ Compilation arm64…"
swiftc -O main.swift Banner.swift -o "$BUILD/arm64" -target arm64-apple-macos15 \
  -framework Cocoa -framework WebKit -framework ServiceManagement
echo "→ Compilation x86_64…"
swiftc -O main.swift Banner.swift -o "$BUILD/x86_64" -target x86_64-apple-macos15 \
  -framework Cocoa -framework WebKit -framework ServiceManagement
lipo -create "$BUILD/arm64" "$BUILD/x86_64" -output "$STAGE/Contents/MacOS/Conso Claude"
rm -f "$BUILD/arm64" "$BUILD/x86_64"

cp -X Info.plist "$STAGE/Contents/Info.plist"
cp -X phrases.json "$STAGE/Contents/Resources/phrases.json"
cp -X AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGE" 2>/dev/null || true
codesign --force -s - "$STAGE"

rm -rf "$APP"
ditto "$STAGE" "$APP"
echo "✅ Build OK : $APP ($(lipo -archs "$APP/Contents/MacOS/Conso Claude"))"

for arg in "$@"; do
  case "$arg" in
    --install)
      pkill -x "Conso Claude" 2>/dev/null || true
      rm -rf "/Applications/$APP"
      ditto "$APP" "/Applications/$APP"
      sleep 1
      open "/Applications/$APP"
      echo "✅ Installé dans /Applications et lancé"
      ;;
    --zip)
      ditto -c -k --keepParent "$APP" "Conso Claude.zip"
      echo "✅ Conso Claude.zip prêt à partager"
      ;;
  esac
done
