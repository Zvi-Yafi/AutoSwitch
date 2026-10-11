#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AutoSwitch.app"
DMG="$ROOT/build/AutoSwitch.dmg"
MODE="${RELEASE_MODE:-test}"
if [ "$MODE" = release ]; then
  SIGN_ID="${CODESIGN_IDENTITY:-}"
  test -n "$SIGN_ID" || { echo "Set CODESIGN_IDENTITY to your Developer ID Application identity." >&2; exit 1; }
  test -n "${EXPECTED_TEAM_ID:-}" || { echo "Set EXPECTED_TEAM_ID to your Apple Developer team." >&2; exit 1; }
fi
STAGE="$(mktemp -d /tmp/AutoSwitch-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
test -d "$APP" || { echo "Build the app first." >&2; exit 1; }
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname AutoSwitch -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [ "$MODE" = release ]; then
  codesign --sign "$SIGN_ID" --timestamp "$DMG"
  SIGN_DETAILS="$(codesign -dv --verbose=2 "$DMG" 2>&1)"
  if [[ "$SIGN_DETAILS" != *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]]; then
    echo "The DMG was not signed by the expected Apple Developer team." >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-AutoSwitch-Notary}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi
echo "DMG ready: $DMG"
