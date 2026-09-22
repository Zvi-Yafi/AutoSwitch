#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/package_release.sh"
rm -rf /Applications/AutoSwitch.app
ditto "$ROOT/build/AutoSwitch.app" /Applications/AutoSwitch.app
echo "Installed to /Applications/AutoSwitch.app"
