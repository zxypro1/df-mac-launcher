#!/bin/zsh
set -e

if ! xcrun --show-sdk-path >/dev/null 2>&1 && [ -d "/Library/Developer/CommandLineTools" ]; then
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

SWIFTC=$(xcrun --find swiftc)
LIPO=$(xcrun --find lipo)
CODESIGN=$(xcrun --find codesign 2>/dev/null || echo "/usr/bin/codesign")
SDK_PATH=$(xcrun --show-sdk-path)

SCRIPT_DIR="${0:A:h}"
OUT_DIR="${1:-${SCRIPT_DIR:h}}"
mkdir -p "$OUT_DIR"
APP_DIR="$OUT_DIR/Dwarf Fortress Launcher.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

"$SWIFTC" \
    -O \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx14.0 \
    "$SCRIPT_DIR/Models.swift" \
    "$SCRIPT_DIR/Views.swift" \
    "$SCRIPT_DIR/App.swift" \
    -o "/tmp/DFMacLauncher_arm64"

"$SWIFTC" \
    -O \
    -sdk "$SDK_PATH" \
    -target x86_64-apple-macosx14.0 \
    "$SCRIPT_DIR/Models.swift" \
    "$SCRIPT_DIR/Views.swift" \
    "$SCRIPT_DIR/App.swift" \
    -o "/tmp/DFMacLauncher_x86_64"

"$LIPO" -create -output "$APP_DIR/Contents/MacOS/DFMacLauncher" "/tmp/DFMacLauncher_arm64" "/tmp/DFMacLauncher_x86_64"
rm -f "/tmp/DFMacLauncher_arm64" "/tmp/DFMacLauncher_x86_64"

chmod +x "$APP_DIR/Contents/MacOS/DFMacLauncher"
"$CODESIGN" --force --deep --sign - "$APP_DIR"
echo "✅ Built & Ad-Hoc Signed Universal App (arm64 + x86_64): $APP_DIR"
