# Tidy

Clean up any message before you send it. Select text in any app, press **⌥⌘C**, and a panel
streams a cleaned-up version from Claude with the changes highlighted. **⌘↩** puts it back
in place of your selection.

## Build & install

1. Install Apple's command line tools if you don't have them: `xcode-select --install`
2. In this folder: `bash build.sh`
   It compiles, installs to /Applications, and opens Tidy (the ✨ wand in your menu bar).
3. Paste your Anthropic API key in Settings. Create one at https://console.anthropic.com/settings/keys
4. Allow Tidy under System Settings › Privacy & Security › Accessibility.

After any rebuild, macOS asks for Accessibility again (the app's signature changes).

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
