# Desktop setup and Settings refinement

> Implement inline using superpowers:executing-plans; user authorized reasonable defaults and this desktop adaptation.

**Goal:** Make connection readiness, setup progress and the return to writing unambiguous while preserving the Mac keyboard workflow.
**Architecture:** Keep the existing AppKit non-activating panel, SwiftUI tabs and Store. Share one connection editor/model between setup and General. Keep Keychain service/account and persisted data formats. Inject dependencies for isolated tests and a DEBUG-only native preview.
**Tech:** SwiftUI, AppKit, Security, SwiftPM/XCTest; macOS 14+, no new dependencies.

## Audit / design
- General always shows a blank key field and saves without validation. Keychain deletes before adding and ignores both results. Change to explicit saved state, deliberate replacement, validation and surfaced persistence failures.
- Key setup auto-advances after a short delay. Keep success visible until Continue; label each step and its next destination.
- Desktop practice uses a real API call, unlike iPhone's recorded sample. Say so before running and retain a sample label with an exit afterward.
- General mixes readiness, preferences and maintenance. Show readiness first, retain model/shortcut/accessibility, collapse maintenance under More options. Keep Modes/Voice/History tabs.

## Constraints
- Preserve ⌥⌘C (or recorded shortcut), ⌘↩, ⌘⇧C, ⌘R, ⌘D, ⌘1–9, ⌘,, Esc, ⌘W and standard field editing.
- Preserve source-app focus, clipboard restoration, rewrite prompts/provider/model IDs and existing persistence.
- No production install, live-key reading by tools, paid API request or Figma write. Native preview uses isolated store, fake key-check and injected sample stream.
- Website reflects any relevant panel/copy changes locally; deployment is outside this requested app refinement.

## Tasks
- [x] Add isolated Mac test dependencies and a shared connection model; test success, rejection, offline, persistence failure, stale completion/cancel and unchanged saved-key state on failure. Update Keychain atomically and throw on failure.
- [x] Reuse connection editor in setup/General; readiness summary, deliberate Continue, named steps, explicit live sample/exit, contextual return action and compact maintenance. Preserve key handling, add regression checks for navigation and preview lifecycle.
- [ ] Build separate DEBUG preview, inspect light/dark states, exercise editing/keyboard navigation, run Mac/Core suites and Release build, update docs/site copy, request independent review.

## Review focus
- Cancelled validation must not overwrite a key after leaving the page.
- Failed replacement must preserve the existing credential and state.
- Settings must not mutate or discard an in-progress draft.
- Sample exit must not receive late streaming text.
- Setup must not claim selection replacement is ready without Accessibility and a registered shortcut.

## Execution record

- Connection/model/navigation suite: 12 Mac tests + 13 shared tests pass.
- Independent reviewer requested preview voice isolation, honest final-step instructions and explicit retained-panel close cancellation; all addressed. Voice and close regressions reproduced failure before fixes.
- Preview built and Release compilation verified. User approved native launch. Light-mode Settings, connection editing/Return to save, setup and sample-label checks completed. An observed shortcut-recorder Escape conflict was addressed. Dark mode and final keyboard retests remain pending because the computer-use bridge timed out on the preview and Dock; see the audit for exact coverage.
- Public-site deployment omitted: this task is desktop refinement, and the normal editor demo is unchanged. Only relevant local copy was updated.
