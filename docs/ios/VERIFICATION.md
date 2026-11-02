# Verification — Tidy iPhone companion

2026-10-30. Isolated worktree: `~/.codex/worktrees/tidy-ios-companion/Tidy`. The original Mac checkout and installed app were not modified. No deployment, account creation, secret import or Figma update.

## Passed

- Baseline Mac debug build before extraction.
- `swift test`: **13 tests, zero failures**. Preserved mode names/instructions, prompt contract, wrapper cleanup, lossless diff reconstruction, bounded diff, mode serialization, invalid/oversized mode collection rejection, SSE text/completion, truncated stream and output token limit failures, cancellation/stale-result protection, exact-request retry, empty results, input cap.
- `swift build -c release --product Tidy`: passed after extraction. Mac UI, storage, Keychain IDs and prompt text retained; shared types moved to TidyCore. Mac stream behavior retains its default completion policy; iOS opts into strict completion.
- iOS Debug and Release builds: app plus Share extension passed. Release excludes `SampleRewrite` and preview controls. No third-party runtime libraries.
- Native flow suite on iPhone 17 Pro / iOS 26.5: **10 tests, zero failures**, Xcode 27.2. `TidyMobile-DesignVerified.xcresult` in `/tmp` contains the run after the Settings redesign. Tests use an explicitly labeled recorded sample, never a real API key.
  1. Actual system share sheet → separate Tidy Share extension → Rewrite → Changes/Final → Copy → nested result Share → Done.
  2. Cancellation and retry.
  3. Custom mode saved in the app, retained across app relaunch, visible in both app and extension.
  4. Exit sample discards the recorded result and clears the known sample draft.
  5. Editing Final clears the prior Copied status.
  6. Missing credential routes to setup before a rewrite and does not expose a completed result action.
  7. Direct rewrite → Original/Changes/Final → Copy → Share.
  8. Completed cleanup sample → Share result → Tidy → Rewrite preserves the sample without a preview error.
  9. Completed shorter sample follows the same round trip without expanding the text.
  10. Settings exposes connection and sample exit immediately, keeps individual modes on their own page, and opens key entry with its primary action disabled until input is present.
- Additional keyboard layout test passed at the **largest accessibility text size in dark mode** after the final layout adjustment (`TidyMobile-DesignLargeFinal.xcresult`). The Connect action remains above the keyboard and reachable. A dummy string was typed but never submitted. The button shortens visually to Connect at accessibility sizes while retaining its full spoken label. Final Release app/extension build passed (`/tmp/tidy-design-release-final.log`).
- Manually verified the existing saved-key state and Start writing returning from the connection sheet through Settings to the editor. No key value was viewed, copied, replaced or submitted, and no rewrite request was sent. Fresh key-validation and saving still require a live credential; that new success transition was not automated against Anthropic.
- Independent source review completed. All four findings addressed: fixture provenance, stale copied status, write-time mode validation, and explicit fallback when a diff exceeds its bound. Regression tests reproduced the state/validation bugs before the fixes.

- Focused review/copy/share workflow also passed in **dark mode** and at **accessibility-extra-extra-extra-large** Dynamic Type. Native screenshots were inspected. The initial largest-size screenshot exposed footer label overlap; the footer now uses shorter status/action copy, preserves natural text height, and exposes the word count as an accessibility value. The brand remains a fixed-size wordmark. Before/after Copy geometry assertions pass. Final can be cleared and retyped while completed-result actions remain disabled for empty text.
- Reduced Motion disables SwiftUI animations and transactions; no custom streaming shimmer is introduced. A separate system-level reduced-motion/VoiceOver audit remains unperformed.

## Visual evidence

Screenshots are real native Simulator captures, not Figma or HTML renders:
- `screenshots/iphone-final.png`
- `screenshots/share-extension-final.png`
- `screenshots/share-extension-changes.png`
- `screenshots/iphone-dark.png`
- `screenshots/iphone-accessibility.png`
- `screenshots/settings-connected.png`
- `screenshots/connection-entry.png`
- `screenshots/connection-ready.png`
- `screenshots/connection-accessibility.png`

## Not claimed as tested

- Real Anthropic generation, account-specific model availability, billing, rate limits, invalid/revoked credentials, and live network recovery. The transport is wired to the existing provider endpoint and prompts, but no real secret was read or used. SSE failure/completion and lifecycle behavior are covered locally.
- Credential write/read across two signed physical-device processes and App Store acceptance. Physical iPhone installation and provisioning subsequently succeeded (see the device-install record below). Unsigned Simulator builds correctly failed Keychain access; signed builds removed that configuration error.
- Share availability in every third-party app. The integration test uses the companion as a controlled system-share-sheet host. Host-provided plain text and attributedContentText are supported; URLs/images/files are not extracted as article text.
- Full VoiceOver/Switch Control audit, OS eviction/background-resume behavior, or device memory profiling. Controls use native accessibility labels, dynamic type, non-color diff marks and reduced-motion-aware transactions. Requests cancel when the editor disappears or scene backgrounds; background generation is not promised.

## Scope boundaries

App Group preferences are local to this iPhone, not cross-device sync. Mac custom modes can be manually imported; voice profile can be pasted. No new backend or Tidy account exists. iOS history, automatic voice learning, per-source-app limits and saved tweak trails are deferred. Share extension distribution suitability needs review against Apple’s Share-vs-Action guidance, linked in AUDIT.md.

## Test-run notes

Earlier failures were expected red tests, unsigned Keychain configuration, and UI-test selectors that did not account for system activity cells, nested share sheets, or a partially visible switch. The user’s sample round-trip screenshot revealed that preview accepted only the original sample. Two regression tests reproduced the failure; preview now also recognizes its two recorded outputs. The extension’s Final editor has a distinct accessibility identifier to avoid ambiguous host/extension snapshots. The complete nine-test suite was rerun green. During the session Xcode changed from 27.1 to 27.2; destinations were refreshed before the final run. Build warnings include skipped App Intents metadata (the app has no App Intents); Simulator test logs also report system accessibility/debugger diagnostics despite the passing run.

## Interactive preview

Open `iOS/TidyMobile.xcodeproj` and run the TidyMobile scheme, then **Try a sample**. The app and system Share extension are interactive native builds. Xcode was corrected from the unrelated XReader project to this worktree’s TidyMobile project and its window title was verified. No external-agent access was granted by this task.

The redesign is installed in the user’s original iPhone Simulator. Automated design tests run on the separate **Tidy UI Checks** device to avoid changing the user's settings or accumulating test modes in their app. One keyboard-check launch was rejected by Simulator as Busy before tests started; explicitly booting the test device resolved it. Device Hub mouse scrolling/dragging remained unresponsive during the earlier investigation, while native accessibility scrolling worked. The shorter Settings root removes the need to scroll through modes to reach setup.

## Physical iPhone preparation — October 30, 2026

- Paired physical target: T iPhone 17 Pro, iOS 26.7.1. Developer Mode is already enabled.
- Fresh arm64 device compilation of the app and Share extension passed with signing disabled (`/tmp/tidy-phone-compile.log`). This is compilation evidence, not an installable or provisioned build.
- Signed build was blocked by Xcode reporting No Accounts and the cached wildcard profile lacking App Groups. The Xcode Apple Accounts panel confirmed no signed-in account; its sign-in dialog was opened for the user. Existing team and App Group identifiers are unchanged.
- Device preparation initially required unlocking. Installation and device credential-sharing verification remain pending account provisioning.

- After the user signed into Xcode, provisioning reached Apple but failed with `PLA Update available`: the development team must accept the latest Program License Agreement. No profiles or install were completed in this retry (`/tmp/tidy-phone-signed.log`). The developer account page was opened for the user to review the agreement.

## Physical installation completed — October 30, 2026

- After agreement acceptance and refreshing Xcode team profiles, the Debug device build succeeded (`/tmp/tidy-phone-refreshed.log`).
- Verified strict code signatures for the app and embedded Share extension. Both profiles include the paired iPhone and expire October 30, 2027. Both carry team Y5V8Y3BH9A, App Group `group.com.tommymassaro.tidy.mobile`, and shared Keychain group `Y5V8Y3BH9A.com.tommymassaro.tidy.mobile.shared`.
- `devicectl device install app` succeeded on T iPhone 17 Pro for `com.tommymassaro.tidy.mobile`, with the embedded extension. Install receipt: `/tmp/tidy-phone-install.json`; installed build: `/tmp/TidyPhoneReady/Build/Products/Debug-iphoneos/TidyMobile.app`.
- The user can now open Tidy on the phone. Physical-device launch, live rewrite, and cross-process credential use remain user test steps. No real credential was viewed or transferred, and no paid rewrite was performed by the agent.
