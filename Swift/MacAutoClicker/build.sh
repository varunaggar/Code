#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build"
APP="$BUILD/MacAutoClicker.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Cleaning previous build..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

echo "==> Compiling Swift sources..."
swiftc \
  -target arm64-apple-macos13.0 \
  -O \
  "$DIR/MacAutoClickerApp.swift" \
  "$DIR/AutoClicker.swift" \
  "$DIR/ContentView.swift" \
  "$DIR/HotKeyManager.swift" \
  "$DIR/AccessibilityHelper.swift" \
  -o "$MACOS/MacAutoClicker"

echo "==> Writing Info.plist..."
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.local.MacAutoClicker</string>
    <key>CFBundleName</key>
    <string>MacAutoClicker</string>
    <key>CFBundleDisplayName</key>
    <string>MacAutoClicker</string>
    <key>CFBundleExecutable</key>
    <string>MacAutoClicker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>MacAutoClicker needs Accessibility access to simulate mouse clicks and register global hotkeys.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing..."
# macOS TCC (accessibility permissions) are tied to the binary's code signature.
# Ad-hoc signing (--sign -) produces a unique hash per build, causing macOS to
# revoke accessibility permission on every rebuild.
#
# To fix this permanently, create a stable self-signed certificate once:
#   1. Open Keychain Access → Certificate Assistant → Create a Certificate
#   2. Name: "MacAutoClicker Dev", Identity type: Self-Signed Root,
#      Certificate type: Code Signing → Continue → Create
#   3. Grant it full trust: double-click it, expand Trust, set "Always Trust"
#
# Then macOS will recognise every rebuild as the same app and keep the permission.
CERT_NAME="MacAutoClicker Dev"
if security find-certificate -c "$CERT_NAME" &>/dev/null; then
    echo "    Using certificate: $CERT_NAME"
    codesign --force --deep --sign "$CERT_NAME" "$APP"
else
    echo "    WARNING: Certificate '$CERT_NAME' not found — using ad-hoc signing."
    echo "    Accessibility permission will be revoked on each rebuild."
    echo "    See instructions above to create a stable signing certificate."
    codesign --force --deep --sign - "$APP"
fi

echo "==> Done: $APP"
echo "    Run with: open '$APP'"
