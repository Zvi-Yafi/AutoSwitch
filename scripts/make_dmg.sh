#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AutoSwitch.app"
DMG="$ROOT/build/AutoSwitch.dmg"
STAGE="$(mktemp -d /tmp/AutoSwitch-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
test -d "$APP" || { echo "Build the app first." >&2; exit 1; }
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname AutoSwitch -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [ "${RELEASE_MODE:-test}" = release ]; then
  SIGN_ID="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | awk '{print $2}' || true)}"
  test -n "$SIGN_ID" || { echo "Developer ID identity required." >&2; exit 1; }
  codesign --sign "$SIGN_ID" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-AutoSwitch-Notary}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi
echo "DMG ready: $DMG"
