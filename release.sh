#!/bin/bash
# Publishes a notarized Tidy release on GitHub. The app's updater and the landing page's
# Download button both use the latest release's Tidy.zip. The notes' "- " bullets are what the
# update window lists, so write them for people using Tidy.
#
# Usage:  bash release.sh 1.4 "- First change
# - Second change"
# Without notes it uses the subjects of the commits since the last release that touched the app
# (not the site or docs).
#
# One-time setup: save your notarization credentials in the keychain as "tidy-notary"
# (an app-specific password from account.apple.com):
#   xcrun notarytool store-credentials tidy-notary --apple-id YOU@EXAMPLE.COM --team-id Y5V8Y3BH9A
# Override the profile name with TIDY_NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
NOTES="${2:-}"
PROFILE="${TIDY_NOTARY_PROFILE:-tidy-notary}"
if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Usage: bash release.sh 1.4 [\"- What changed\"]"
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash your changes first; a release is built from a clean tree."
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "v$VERSION already exists."
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "No notarization credentials saved as \"$PROFILE\". See the top of release.sh."
  exit 1
fi

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -z "$NOTES" ]; then
  NOTES="$(git log --format='- %s' ${LAST_TAG:+"$LAST_TAG"..}HEAD -- . ':!site' ':!docs' ':!CLAUDE.md' ':!wrangler.jsonc' | grep -v '^- Release ' || true)"
fi
if [ -z "$NOTES" ]; then
  echo "No app changes since $LAST_TAG to list. Pass the notes: bash release.sh $VERSION \"- What changed\""
  exit 1
fi

echo "==> Version $VERSION"
BUILD_NUMBER="$(git rev-list --count HEAD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD_NUMBER + 1))" Resources/Info.plist
git diff --quiet Resources/Info.plist || git commit -q -m "Release $VERSION" Resources/Info.plist # a rerun after a failed notarization has nothing new

TIDY_RELEASE=1 bash build.sh

echo "==> Notarizing (this can take a few minutes)"
ZIP="build/Tidy.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Tidy.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/Tidy.app
rm -f "$ZIP"
ditto -c -k --keepParent build/Tidy.app "$ZIP"
spctl --assess --type execute build/Tidy.app

echo "==> Publishing v$VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "Tidy $VERSION" --notes "$NOTES"
echo "==> Done. https://github.com/tmass1/tidy/releases/tag/v$VERSION"
