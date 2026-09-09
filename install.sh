#!/bin/bash
# Builds and installs PortKiller into /Applications, then launches it.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -x PortKiller 2>/dev/null || true
rm -rf /Applications/PortKiller.app
cp -R dist/PortKiller.app /Applications/
open /Applications/PortKiller.app
echo "installed: look for the ⚡ icon in the menu bar"
