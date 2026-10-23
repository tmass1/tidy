# Tidy

Clean up any message before you send it. Select text in any app, press **⌥⌘C**, and a panel
streams a cleaned-up version from Claude with the changes highlighted. **⌘↩** puts it back
in place of your selection.

**Download:** https://tmass1.github.io/tidy/ (macOS 14+, Apple Silicon). Tidy updates itself from
the [latest release](https://github.com/tmass1/tidy/releases/latest).

## Build & install from source

1. Install Apple's command line tools if you don't have them: `xcode-select --install`
2. In this folder: `bash build.sh`
   It compiles, installs to /Applications, and opens Tidy (the ✨ wand in your menu bar).
3. Paste your Anthropic API key in Settings. Create one at https://console.anthropic.com/settings/keys
4. Allow Tidy under System Settings › Privacy & Security › Accessibility.

With a Developer ID certificate in your keychain, `build.sh` signs with it and the Accessibility
grant survives rebuilds. Without one it signs ad-hoc, and macOS asks for Accessibility again after
every rebuild.

## Releasing

`bash release.sh 1.1` bumps the version, builds a signed and notarized `Tidy.zip`, tags `v1.1` and
publishes a GitHub release. The app's updater and the landing page's Download button both use the
latest release. See the top of `release.sh` for the one-time notarization setup.

The landing page lives in `site/` and deploys to GitHub Pages on every push that changes it.

## In the panel

| Key | Does |
| --- | --- |
| ⌘↩ | Replace your selection (or paste into the app you came from) |
| ⌘⇧C | Copy the result |
| ⌘1–9 | Switch mode and rerun |
| ⌘R | Run again |
| ⌘D | Toggle Changes / Final (edit in Final) |
| ↩ in the tweak field | Rework the result: "warmer close", "mention Friday" |
| esc | Cancel |

## Files

- Settings & voice profile: `defaults read com.tommymassaro.tidy`
- Modes and history: `~/Library/Application Support/Tidy/`
- API key: your login Keychain (service `com.tommymassaro.tidy`)
