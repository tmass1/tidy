#!/bin/bash
# Build an isolated, DEBUG-only native UI preview. Does not install or launch Tidy.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product Tidy
TIDY_PREVIEW_BIN="$(swift build --show-bin-path)/Tidy"
TIDY_PREVIEW_APP="build/Tidy Preview.app"
mkdir -p "$TIDY_PREVIEW_APP/Contents/MacOS" "$TIDY_PREVIEW_APP/Contents/Resources"
cp "$TIDY_PREVIEW_BIN" "$TIDY_PREVIEW_APP/Contents/MacOS/Tidy"
cp Resources/AppIcon.png "$TIDY_PREVIEW_APP/Contents/Resources/AppIcon.png"
python3 - <<'PY'
import plistlib
from pathlib import Path
info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
info.update(CFBundleIdentifier='com.tommymassaro.tidy.designpreview', CFBundleName='Tidy Preview',
            CFBundleDisplayName='Tidy Preview', CFBundleIconFile='AppIcon.png', LSUIElement=False)
Path('build/Tidy Preview.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$TIDY_PREVIEW_APP"
printf '%s\n' "Built $PWD/$TIDY_PREVIEW_APP"
printf '%s\n' 'Open this app for an isolated preview; optional --setup or --disconnected arguments select those states.'
