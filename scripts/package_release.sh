#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${RELEASE_MODE:-test}"
case "$MODE" in test|release) ;; *) echo "RELEASE_MODE must be test or release" >&2; exit 1 ;; esac
SIGN_ID="${CODESIGN_IDENTITY:-}"
if [ "$MODE" = release ]; then
  if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | awk '{print $2}' || true)"
  fi
  if [ -z "$SIGN_ID" ]; then
    echo "A Developer ID Application identity is required for public distribution." >&2
    exit 1
  fi
fi
# Keep compiler-generated resource fallback paths free of personal home directories.
BUILD_ROOT="$(mktemp -d /tmp/AutoSwitch-build.XXXXXX)"
trap 'rm -rf "$BUILD_ROOT"' EXIT
BINARIES=()
RESOURCE_BUNDLE=""
for ARCH in arm64 x86_64; do
  BUILD_ARGS=(-c release --triple "$ARCH-apple-macosx13.0" --scratch-path "$BUILD_ROOT/$ARCH" -debug-info-format none -Xswiftc -file-prefix-map -Xswiftc "$ROOT=/AutoSwitch")
  swift build "${BUILD_ARGS[@]}"
  BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
  BINARIES+=("$BIN_DIR/AutoSwitch")
  if [ -z "$RESOURCE_BUNDLE" ]; then RESOURCE_BUNDLE="$BIN_DIR/AutoSwitch_AutoSwitch.bundle"; fi
done
APP="$ROOT/build/AutoSwitch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/AutoSwitch"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp "$ROOT/Resources/AutoSwitch.icns" "$APP/Contents/Resources/"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"
if [ "$MODE" = test ]; then
  # A local test signature exposes no personal signing certificate.
  codesign --force --deep --sign - --timestamp=none --options runtime --entitlements "$ROOT/AutoSwitch-Distribution.entitlements" "$APP"
else
  codesign --force --deep --sign "$SIGN_ID" --timestamp --options runtime --entitlements "$ROOT/AutoSwitch-Distribution.entitlements" "$APP"
  DETAILS="$(codesign -dv --verbose=2 "$APP" 2>&1)"
  if [[ "$DETAILS" != *"Authority=Developer ID Application"* ]]; then
    echo "The signing identity is not Developer ID Application." >&2
    exit 1
  fi
fi
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/AutoSwitch"
echo "Built: $APP ($MODE)"
