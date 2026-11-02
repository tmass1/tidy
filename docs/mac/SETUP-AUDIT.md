# Desktop setup and Settings audit

Source: the native Swift/AppKit Tidy Mac app in this isolated worktree. The original checkout is unchanged. After design approval, the signed desktop build was installed in /Applications/Tidy.app; the previous app is preserved as a backup. No Figma changes.

## Findings and changes

- Settings showed a blank key field even after saving, and accepted keys without validation. Both setup and General now use one connection editor: explicit saved state, Change key, validation, error states and checked persistence. The Keychain service/account are unchanged. Replacement uses update/add rather than delete-first; failed writes retain the cached key and saved state.
- Setup automatically advanced before people could read the success. The four steps now have names, keep success visible and wait for Continue. Accessibility state still polls, without automatically navigating.
- General mixed essential setup and maintenance. It now starts with readiness and a return-to-writing action; model, shortcut and Accessibility stay visible. More options holds login, clipboard restoration, updates and setup walkthrough. The menu-bar Check for Updates action expands that section so the result stays visible. Modes/Voice/History retain their existing tabs.
- The final setup step implied any selected draft would be rewritten, although the setup hotkey runs the built-in sample. It now explains Start writing exits setup before using your own selection. Missing Accessibility or a conflicted shortcut leads to pasted-draft guidance.
- Mac practice is a live API request, unlike iPhone's recorded sample. The walkthrough says so before execution. The editor retains a sample label and Exit sample after completion.

## Keyboard and product boundaries

Existing keyboard mappings remain unchanged. A new priority guard lets the shortcut recorder consume keys before panel navigation: Esc cancels recording without also stepping setup backward. Closing the panel ends recording. The non-activating panel, global shortcut registration, source application, copy/paste implementation, clipboard restoration, prompt content, model IDs, mode shortcuts and history formats remain. Injected transports/defaults are test/preview seams with the same production defaults.

The separate DEBUG preview uses a different bundle ID, temporary preferences/files, injected key read/write/check and recorded rewrites. It never constructs the production AppDelegate/Store.shared; it does not register a global hotkey or run updater checks. Voice learning is blocked at the Store boundary. Opening the preview bundle automatically selects this path even without launch arguments.

## Verification

- Release build passed; the isolated DEBUG preview is built at `build/Tidy Preview.app`.
- `swift test`: 12 Mac tests and 13 shared tests passed. Coverage includes validation success/rejection/offline, persistence failure, cancelled/late validation, explicit panel-close cancellation of validation and shortcut recording, preserved existing key on failed replacement, readiness combinations, settings preserving draft/result/source, sample completion/exit and late output, and preview voice isolation.
- Reviewer findings about preview voice networking and ambiguous shortcut instructions were addressed. A retained-window cancellation concern was reproduced: close originally allowed a delayed check to write. The regression now passes after explicit cancellation on close. Voice isolation also had a failing regression before the fix.
- Connection checks and rewrite tests use controlled dependencies, not a real key. No paid generation, real credential replacement, permission changes or public deployment was performed. The local installation is recorded below.
- Local site wording reflects checked keys and the optional live sample. The normal editor demo did not change and no public website was deployed.
- User approved launching the isolated preview. Native light-mode inspection confirmed the General readiness summary, Change key, field editing with ⌘A, Return to connect, visible saved state, expanded More options, all four setup screens, and recorded sample completion with its persistent label/Exit sample control.
- Native testing exposed Esc also stepping setup backward while the shortcut recorder was active. The new guard addresses that conflict; a regression covers ending recording on panel close. Named progress captions and preview-only shortcut guidance were corrected after inspection.
- The computer-use bridge then timed out on both the preview and Dock. Dark-mode inspection, the native Escape retest, sample-exit click and remaining keyboard checks are still pending. The updated bundle is built, but the running preview may be the earlier build; quit/reopen it before those checks. Global selection/replacement and physical source-app focus behavior are not claimed as retested.

## Approved local installation — October 30, 2026

- After the user accepted the design, reran all 25 tests and built the production bundle with the existing Developer ID, team Y5V8Y3BH9A. Installed and prior bundles have identical designated signing requirements.
- Installed `/Applications/Tidy.app`; strict code-signature verification passed. Previous app retained at `/Applications/.Tidy-backup-20261030-140319.app`. User preferences, history, credentials and permissions were not changed by installation.
- Computer-use connection still timed out when inspecting the installed app. The user must quit/reopen Tidy to load the update; launch and live selection/replacement verification remain pending. No shell-based UI fallback was used.
