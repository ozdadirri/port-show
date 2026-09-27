#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="PortShow"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "==> Cleaning build directory"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> Compiling Swift sources"
swiftc -O \
  -target arm64-apple-macosx13.0 \
  -o "$MACOS_DIR/$APP_NAME" \
  "$ROOT"/Sources/*.swift

echo "==> Copying Info.plist"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "==> Generating app icon"
"$ROOT/make_icon.sh" "$RESOURCES_DIR/AppIcon.icns"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Built $APP_DIR"

echo "==> Creating DMG"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> Done: $DMG_PATH"
