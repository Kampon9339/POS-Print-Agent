#!/usr/bin/env bash
set -e

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="/tmp/flutter/bin:$PATH"

echo "Building POS Print Agent for macOS Desktop..."
flutter build macos --debug || true

BUILT_APP="build/macos/Build/Products/Debug/pos_print_agent.app"
TARGET_APP="/tmp/POS Print Agent.app"

killall pos_print_agent 2>/dev/null || true
rm -rf "$TARGET_APP"
cp -R "$BUILT_APP" "$TARGET_APP"
/usr/bin/xattr -cr "$TARGET_APP"
/usr/bin/codesign --force --deep --sign - "$TARGET_APP"

echo "Launching POS Print Agent..."
open "$TARGET_APP"
