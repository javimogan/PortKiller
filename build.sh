#!/bin/bash
# Builds PortKiller.app (a menu-bar-only agent) into ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/PortKiller.app"
VERSION="${VERSION:-1.1}"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PortKiller "$APP/Contents/MacOS/PortKiller"

# App icon, built from the single 1024px source. The menu bar keeps using an SF Symbol, so
# this only shows up in Finder, Login Items and the app's own alerts — which is precisely
# where a generic blank icon looks unfinished.
ICONSET="dist/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" assets/icon.png \
       --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PortKiller</string>
    <key>CFBundleDisplayName</key><string>PortKiller</string>
    <key>CFBundleIdentifier</key><string>com.javimogan.portkiller</string>
    <key>CFBundleExecutable</key><string>PortKiller</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
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
