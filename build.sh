#!/bin/bash
# Builds Tidy, installs it to /Applications and opens it.
# Usage:  bash build.sh        (output is also saved to build.log)
set -euo pipefail
cd "$(dirname "$0")"
exec > >(tee build.log) 2>&1

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run this, accept the prompt, then run build.sh again:"
  echo "  xcode-select --install"
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
codesign --force --sign - --identifier com.tommymassaro.tidy "$APP"

echo "==> Installing to /Applications"
pkill -x Tidy 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Tidy.app
ditto "$APP" /Applications/Tidy.app

# A rebuilt app has a new signature, so macOS ignores the old Accessibility grant.
# Clear it so Tidy asks again cleanly instead of silently failing.
tccutil reset Accessibility com.tommymassaro.tidy >/dev/null 2>&1 || true

open /Applications/Tidy.app
echo "==> Done. Tidy is in your menu bar."
