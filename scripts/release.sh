#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Step 1/3: Building and signing app"
RELEASE_MODE=release "$ROOT/scripts/package_release.sh"

echo ""
echo "==> Step 2/3: Notarizing app"
"$ROOT/scripts/notarize_release.sh"

echo ""
echo "==> Step 3/3: Creating DMG"
RELEASE_MODE=release "$ROOT/scripts/make_dmg.sh"

echo ""
echo "=================================================="
echo "Release ready: $ROOT/build/AutoSwitch.dmg"
echo "Send this file to your testers."
echo "=================================================="
