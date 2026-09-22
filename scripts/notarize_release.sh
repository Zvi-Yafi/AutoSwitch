#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AutoSwitch.app"
ZIP="$ROOT/build/AutoSwitch-notarize.zip"

PROFILE="${NOTARY_PROFILE:-AutoSwitch-Notary}"

if [ ! -d "$APP" ]; then
  echo "Error: $APP does not exist. Run scripts/package_release.sh first." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
Error: notarytool keychain profile "$PROFILE" not found.

Run this once to set it up (one-time setup):

  xcrun notarytool store-credentials "$PROFILE" \\
    --apple-id "YOUR_APPLE_ID" \\
    --team-id "YOUR_TEAM_ID" \\
    --password "<your-app-specific-password>"

Then re-run this script.
EOF
  exit 1
fi

CODESIGN_OUT="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
echo "Signing identity on app:"
echo "$CODESIGN_OUT" | grep -E "Authority|TeamIdentifier|Runtime" || true

if [[ "$CODESIGN_OUT" != *"Authority=Developer ID Application"* ]]; then
  echo "Error: App is not signed with Developer ID Application." >&2
  echo "Re-run: scripts/package_release.sh (make sure the Developer ID cert is in your keychain)." >&2
  exit 1
fi

echo "Zipping for notarization..."
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notary service (this can take 1-5 minutes)..."
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$PROFILE" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$ZIP"
echo ""
echo "Notarization complete: $APP"
