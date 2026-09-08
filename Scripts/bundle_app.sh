#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "Building Stanza (Release)..."
swift build -c release

APP_NAME="Stanza"
APP_DIR="$DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating bundle structure at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$DIR/.build/release/Stanza" "$MACOS_DIR/Stanza"
chmod +x "$MACOS_DIR/Stanza"

# Copy AppIcon if present
if [ -f "$DIR/Sources/Stanza/Resources/AppIcon.icns" ]; then
    cp "$DIR/Sources/Stanza/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Create Info.plist
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Stanza</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.stanza.player</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Stanza</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Stanza. All rights reserved.</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Audio Files</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>public.mp3</string>
                <string>com.pkware.zip-archive</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Strip extended attributes
xattr -cr "$APP_DIR"

# Check if an Apple Developer identity is installed in Keychain
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}')

if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | awk -F'"' '{print $2}')
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing Stanza.app with Developer Identity: $SIGNING_IDENTITY..."
    codesign --force --deep --options runtime --timestamp --entitlements "$DIR/entitlements.plist" --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    echo "No Apple Developer certificate found in Keychain. Using ad-hoc signature..."
    codesign --force --deep --sign - "$APP_DIR"
fi

# Verify signature integrity
codesign -vvv --deep --strict "$APP_DIR"

echo "Stanza.app successfully packaged and signed at: $APP_DIR"


