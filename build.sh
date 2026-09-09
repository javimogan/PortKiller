#!/bin/bash
# Builds PortKiller.app (a menu-bar-only agent) into ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/PortKiller.app"
VERSION="1.0"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PortKiller "$APP/Contents/MacOS/PortKiller"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PortKiller</string>
    <key>CFBundleDisplayName</key><string>PortKiller</string>
    <key>CFBundleIdentifier</key><string>com.javimogan.portkiller</string>
    <key>CFBundleExecutable</key><string>PortKiller</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for the login-item API and for Gatekeeper on this machine.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign failed, app still runs"

echo "built $APP"
