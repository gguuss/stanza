#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="1.1.0"
DMG_NAME="Stanza-${VERSION}.dmg"
OUTPUT_DMG="$DIR/build/$DMG_NAME"
STAGING_DIR="$DIR/build/dmg_staging"

# 1. Build release application bundle
echo "==> Building Stanza application bundle..."
./Scripts/bundle_app.sh

# 2. Generate DMG background graphic
echo "==> Generating DMG background..."
python3 Scripts/generate_dmg_background.py

# 3. Setup staging folder
echo "==> Preparing staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$DIR/build/Stanza.app" "$STAGING_DIR/"

# 4. Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "create-dmg not found. Installing via Homebrew..."
    brew install create-dmg
fi

# 5. Build DMG with drag-to-Applications layout
echo "==> Creating $DMG_NAME installer..."
rm -f "$OUTPUT_DMG"
create-dmg \
  --volname "Stanza" \
  --volicon "$DIR/Sources/Stanza/Resources/AppIcon.icns" \
  --background "$DIR/Scripts/dmg_background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 110 \
  --text-size 13 \
  --icon "Stanza.app" 180 190 \
  --hide-extension "Stanza.app" \
  --app-drop-link 480 190 \
  --format UDZO \
  --filesystem HFS+ \
  --overwrite \
  "$OUTPUT_DMG" \
  "$STAGING_DIR"

# Clean up staging
rm -rf "$STAGING_DIR"

# Sign the DMG
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}')
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | awk -F'"' '{print $2}')
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "==> Signing DMG with Developer Identity: $SIGNING_IDENTITY..."
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$OUTPUT_DMG"
else
    echo "==> Signing DMG with ad-hoc signature..."
    codesign --force --sign - "$OUTPUT_DMG"
fi

echo "==> Successfully created DMG installer at: $OUTPUT_DMG"


