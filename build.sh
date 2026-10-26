#!/bin/bash
# Builds Tidy, installs it to /Applications and opens it.
# Usage:  bash build.sh        (output is also saved to build.log)
#
# Signing: uses your "Developer ID Application" identity when the login keychain has one
# (override with TIDY_SIGN_IDENTITY). A stable signature means macOS keeps the Accessibility
# grant across rebuilds. Without one it falls back to ad-hoc signing and resets the grant.
#
# release.sh runs this with TIDY_RELEASE=1: it signs for distribution (hardened runtime and a
# secure timestamp, both needed for notarization) and stops before installing.
set -euo pipefail
cd "$(dirname "$0")"
exec > >(tee build.log) 2>&1

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run this, accept the prompt, then run build.sh again:"
  echo "  xcode-select --install"
  exit 1
fi

IDENTITY="${TIDY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
RELEASE="${TIDY_RELEASE:-0}"
if [ "$RELEASE" = 1 ] && [ -z "$IDENTITY" ]; then
  echo "Releases need a Developer ID Application certificate in your login keychain."
  exit 1
fi

echo "==> Compiling"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Tidy"

echo "==> Bundling"
APP="build/Tidy.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp "$BIN" "$APP/Contents/MacOS/Tidy"
cp Resources/Info.plist "$APP/Contents/Info.plist"

for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing"
if [ -n "$IDENTITY" ]; then
  echo "    $IDENTITY"
  if [ "$RELEASE" = 1 ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier com.tommymassaro.tidy "$APP"
  else
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" --identifier com.tommymassaro.tidy "$APP"
  fi
else
  echo "    ad-hoc (no Developer ID found)"
  codesign --force --sign - --identifier com.tommymassaro.tidy "$APP"
fi
codesign --verify --strict "$APP"

if [ "$RELEASE" = 1 ]; then
  echo "==> Built $APP for release"
  exit 0
fi

echo "==> Installing to /Applications"
# The Accessibility grant is tied to the signature's team. Note the installed copy's team
# before replacing it ("" for ad-hoc or none).
team_of() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | grep -v "not set" || true; }
OLD_TEAM="$( [ -d /Applications/Tidy.app ] && team_of /Applications/Tidy.app || echo "none")"
NEW_TEAM="$(team_of "$APP")"
pkill -x Tidy 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Tidy.app
ditto "$APP" /Applications/Tidy.app

if [ -z "$NEW_TEAM" ] || [ "$OLD_TEAM" != "$NEW_TEAM" ]; then
  # An ad-hoc build has a new signature every time, and switching between ad-hoc and Developer ID
  # changes it too. Either way macOS ignores the old grant while still showing Tidy switched on,
  # so clear it and let Tidy ask again cleanly.
  echo "    Signature changed: resetting Tidy's Accessibility permission"
  tccutil reset Accessibility com.tommymassaro.tidy >/dev/null 2>&1 || true
fi

open /Applications/Tidy.app
echo "==> Done. Tidy is in your menu bar."
