#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP_NAME="Cue"
VOLUME_NAME="Cue"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-root"
APP_SRC="${2:-}"

if [[ -z "$APP_SRC" ]]; then
  APP_SRC="$(find "$ROOT/DerivedData/Build/Products" -name "${APP_NAME}.app" -type d | head -n 1)"
fi

if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "Cue.app not found. Build a Release binary first." >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_SRC" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
mkdir -p "$DIST"
rm -f "$DMG"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Created $DMG"
