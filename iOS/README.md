# Tidy for iPhone — companion prototype

Open `TidyMobile.xcodeproj` in Xcode and run the **TidyMobile** scheme on an iPhone simulator. The app requires iOS 17+. No runtime dependencies were added. `project.yml` is the source for the project; regenerate with `xcodegen generate --spec iOS/project.yml` from the repository root if changing target configuration. XcodeGen is not needed to open the included project.

## Try it

In a Debug build, tap **Try a sample**. Choose a mode, tap **Rewrite**, then review **Original**, **Changes**, and editable **Final**. Try cancellation, Retry, Copy result and Share result. The lavender notice explicitly identifies a recorded sample; this does not call Anthropic. Clean up and Shorter have sample outputs; other modes display the same illustrative cleanup. Custom instructions require live mode. The sample is based on the Mac app’s existing demo.

**Share sample to Tidy** opens the real system share sheet. Choose **Tidy** to run the separate Share extension process. This is also the automated integration test host. In other apps that share selected text: select text → Share → Tidy → choose a mode → Rewrite → Copy result → Done → manually paste. URL-only shares and images are deliberately unsupported. A host app controls whether selected text has a Share action; Tidy cannot replace text globally on iOS.

You can also send either completed sample back through **Share result → Tidy**. Preview recognizes the original sample and both recorded results, preserving an already-shortened result. Edited or unrelated text still requires live mode.

## Live rewrites

Tap **Exit sample** if you are previewing, then **Set up Tidy → Add API key** (or open Settings → Add API key). Enter your own Anthropic API key and tap **Connect to Anthropic**. A free models request validates it. Successful saving exits sample mode and shows **You’re ready to write → Start writing**. Settings now shows the saved connection instead of an empty key field; replacement/removal live under **Manage connection**.

The key is saved only to the shared, device-local Keychain; it is not compiled into the app, logged, included in settings, or imported from the Mac. Rewriting sends the text, selected instructions and enabled voice profile directly to Anthropic using the existing Mac prompts/model IDs. The release build contains no sample transport. Modes and voice have their own pages under Settings, keeping connection and sample controls easy to find.

The existing Mac IDs are retained verbatim (Haiku/Sonnet/Opus 5.5); live availability and usage billing depend on your Anthropic account. No live credential was used during prototype development.

## Signing on a physical device

Use your development team for both targets and enable/register:
- App Group: `group.com.tommymassaro.tidy.mobile`
- Shared Keychain group: `$(AppIdentifierPrefix)com.tommymassaro.tidy.mobile.shared`
- App bundle: `com.tommymassaro.tidy.mobile`
- Extension bundle: `com.tommymassaro.tidy.mobile.share`

The app and extension must have matching entitlements. Simulator builds should keep ad-hoc code signing enabled (`CODE_SIGN_IDENTITY=-`); disabling all signing removes Keychain access-group entitlements and correctly produces an error. Development provisioning and installation on the paired iPhone 17 Pro succeeded on October 30, 2026. The app and extension have matching signed groups; physical-device credential sharing still needs a live user check. App Store distribution is a separate step.

## Shared vs synchronized

`TidyCore` is shared source code used by Mac, iPhone and extension. The iOS App Group shares settings **on one iPhone**, not across devices. Import your Mac `~/Library/Application Support/Tidy/modes.json` with Settings → Manage modes → Import Mac modes. Same IDs update; other modes remain. Voice instructions can be pasted manually. There is no Tidy account, new backend, iCloud sync or automatic key migration.

History, automatic voice learning, per-source-app character limits, saved tweak trails and automatic cross-device sync are outside this first companion milestone. Tweaks use the existing prompt and current Final text. There is no automatic replacement in another app.

## Tests

From the repository root:

```sh
swift test
swift build -c release --product Tidy
xcodebuild -project iOS/TidyMobile.xcodeproj -scheme TidyMobile \
  -destination 'platform=iOS Simulator,name=Tidy UI Checks' \
  CODE_SIGN_IDENTITY=- test
```

Use a separate, empty Simulator named **Tidy UI Checks** for UI tests. The tests create custom modes and change preview preferences; keep them away from your everyday Simulator. The UI suite exercises a clearly labeled sample transport; it does not prove real Anthropic responses or device credential sharing. See `docs/ios/VERIFICATION.md` for the observed results and remaining checks, and `docs/ios/AUDIT.md` for the architecture audit.
