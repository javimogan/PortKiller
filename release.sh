#!/bin/bash
# Builds a drag-to-Applications DMG.
#
# Signs and notarises it when a Developer ID is available, so downloads open with no warning:
#   1. Apple Developer Program membership (99 USD/year) -> "Developer ID Application" certificate
#   2. xcrun notarytool store-credentials portkiller \
#          --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#   3. ./release.sh
# Without that certificate it still produces a working DMG, only ad-hoc signed: macOS will warn
# on first launch and the user has to allow it in System Settings > Privacy & Security.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-portkiller}"
DMG="dist/PortKiller-$VERSION.dmg"
STAGE="dist/dmg"

bold=$'\033[1m'; dim=$'\033[2m'; yellow=$'\033[33m'; green=$'\033[32m'; reset=$'\033[0m'

VERSION="$VERSION" ./build.sh

# A Developer ID is the only identity Gatekeeper accepts from an unknown machine; an
# "Apple Development" certificate is for your own devices and does not count.
# `|| true`: no match is the normal case here, and pipefail would otherwise abort the script.
IDENTITY="${DEVELOPER_ID:-$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)}"

if [[ -n "$IDENTITY" ]]; then
  echo "${dim}signing as${reset} $IDENTITY"
  # Hardened runtime and a secure timestamp are both required for notarisation.
  codesign --force --deep --options runtime --timestamp \
           --sign "$IDENTITY" dist/PortKiller.app
else
  echo "${yellow}no Developer ID found — the DMG will be ad-hoc signed${reset}"
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R dist/PortKiller.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -quiet -volname "PortKiller" -srcfolder "$STAGE" \
               -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$DMG"
  echo "${dim}notarising… (a few minutes)${reset}"
  if xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait; then
    # Stapling puts the ticket inside the DMG so it opens even offline.
    xcrun stapler staple "$DMG"
    echo "${green}✓${reset} ${bold}$DMG${reset} signed, notarised and stapled"
    exit 0
  fi
  echo "${yellow}notarisation failed — the DMG is signed but will still warn on first launch${reset}"
fi

echo "${green}✓${reset} ${bold}$DMG${reset} $(du -h "$DMG" | cut -f1)"
echo "${dim}unnotarised: users get \"Apple could not verify\" and must allow it in"
echo "System Settings > Privacy & Security, or run:"
echo "  xattr -dr com.apple.quarantine /Applications/PortKiller.app${reset}"
