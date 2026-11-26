#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
if [ -f "/tmp/flutter/bin/internal/shared.sh" ]; then
  export PATH="/tmp/flutter/bin:$PATH"
fi

echo "===================================================="
echo "1. Preparing POS Print Agent macOS App Bundle..."
echo "===================================================="
if command -v flutter >/dev/null 2>&1 && [ -f "$(dirname "$(command -v flutter)")/internal/shared.sh" ]; then
  flutter build macos --release || true
fi

if [ -d "$PROJECT_ROOT/build/macos/Build/Products/Release/pos_print_agent.app" ]; then
  SOURCE_APP="$PROJECT_ROOT/build/macos/Build/Products/Release/pos_print_agent.app"
elif [ -d "$PROJECT_ROOT/build/macos/Build/Products/Debug/pos_print_agent.app" ]; then
  SOURCE_APP="$PROJECT_ROOT/build/macos/Build/Products/Debug/pos_print_agent.app"
else
  echo "Error: Built macOS app not found in build/macos/Build/Products/"
  exit 1
fi
echo "Using app bundle: $SOURCE_APP"

STAGING_DIR="/tmp/pos_print_agent_installer_staging"
DMG_ROOT="$STAGING_DIR/dmg_root"
PKG_ROOT="$STAGING_DIR/pkg_root/Applications"
DIST_DIR="$PROJECT_ROOT/dist/macos"

rm -rf "$STAGING_DIR"
mkdir -p "$DMG_ROOT" "$PKG_ROOT" "$DIST_DIR"

CLEAN_APP="$DMG_ROOT/POS Print Agent.app"
cp -R "$SOURCE_APP" "$CLEAN_APP"

echo "===================================================="
echo "2. Stripping extended attributes & signing .app..."
echo "===================================================="
/usr/bin/xattr -cr "$CLEAN_APP"
/usr/bin/codesign --force --deep --sign - \
  --entitlements "$PROJECT_ROOT/macos/Runner/Release.entitlements" \
  "$CLEAN_APP"

echo "===================================================="
echo "3. Creating macOS Package (.pkg) Wizard Installer..."
echo "===================================================="
cp -R "$CLEAN_APP" "$PKG_ROOT/POS Print Agent.app"
TMP_PKG="/tmp/POS-Print-Agent-macOS-Installer.pkg"
FINAL_PKG="$DIST_DIR/POS-Print-Agent-macOS-Installer.pkg"
rm -f "$TMP_PKG" "$FINAL_PKG"

/usr/bin/pkgbuild \
  --root "$STAGING_DIR/pkg_root" \
  --identifier "com.posprintagent.desktop" \
  --version "1.0.0" \
  --install-location "/" \
  "$TMP_PKG"

cp "$TMP_PKG" "$FINAL_PKG"

echo "===================================================="
echo "4. Creating macOS Portable .zip Archive & Ready .app..."
echo "===================================================="
FINAL_ZIP="$DIST_DIR/POS-Print-Agent-macOS-App.zip"
rm -f "$FINAL_ZIP"
/usr/bin/ditto -c -k --keepParent "$CLEAN_APP" "$FINAL_ZIP"
rm -rf "$DIST_DIR/POS Print Agent.app"
cp -R "$CLEAN_APP" "$DIST_DIR/POS Print Agent.app"
rm -rf "/tmp/POS Print Agent.app"
cp -R "$CLEAN_APP" "/tmp/POS Print Agent.app"

echo "===================================================="
echo "5. Creating macOS Disk Image (.dmg) Installer..."
echo "===================================================="
ln -s /Applications "$DMG_ROOT/Applications"
TMP_DMG="/tmp/POS-Print-Agent-macOS-Installer.dmg"
FINAL_DMG="$DIST_DIR/POS-Print-Agent-macOS-Installer.dmg"
rm -f "$TMP_DMG" "$FINAL_DMG"

if /usr/bin/hdiutil create \
  -volname "POS Print Agent Installer" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$TMP_DMG" 2>/dev/null; then
  cp "$TMP_DMG" "$FINAL_DMG"
fi

echo "===================================================="
echo "macOS Installers built successfully in dist/macos/:"
echo "  - DMG Installer : $FINAL_DMG"
echo "  - PKG Installer : $FINAL_PKG"
echo "  - ZIP Bundle    : $FINAL_ZIP"
echo "===================================================="
