# Tidy

A native macOS menu bar app that cleans up messages before you send them. Select text in any
app, press a global hotkey (default ⌥⌘C), and a floating panel streams a rewritten version from
the Anthropic API with word-level changes highlighted. ⌘↩ pastes it back over the selection.

Owner: Tommy Massaro (product designer / design engineer). He designs desktop-first and cares
about polish; treat UI details as product decisions, not afterthoughts.

**Read `docs/HANDOFF.md` first.** It has current status, the first tasks, and known risks.

## Stack

- Swift Package (no Xcode project), single executable target, **no third-party dependencies**
- AppKit shell (status item, NSPanel, Carbon hotkey) + SwiftUI views hosted inside it
- macOS 14+ (Apple Silicon); `swift-tools-version:5.9`, so it compiles in **Swift 5 language mode**
- Anthropic Messages API over `URLSession.bytes` with SSE streaming; API key in the login Keychain

## Commands

```bash
bash build.sh            # compile (release, arm64), bundle Tidy.app, ad-hoc sign, install to /Applications, launch
swift build              # compile only (fast check while iterating)
tail -50 build.log       # build.sh writes all its output here
log stream --predicate 'process == "Tidy"' --level debug   # runtime logs (NSLog)
```

Requires Apple's command line tools (`xcode-select --install`). Full Xcode isn't required.

## Layout

```
Package.swift
build.sh                     build + bundle + sign + install (also resets the Accessibility grant, see Gotchas)
Resources/Info.plist         LSUIElement=true (no Dock icon), bundle id com.tommymassaro.tidy
Resources/AppIcon.png        1024px source; build.sh turns it into AppIcon.icns with sips/iconutil
Sources/Tidy/
  TidyApp.swift              @main entry, String helpers (trimmed, wordCount, firstLine)
  AppDelegate.swift          status item + menu, hotkey → trigger(), settings window, hidden Edit menu
  HotKey.swift               Shortcut model (Carbon keycodes/modifiers) + HotKeyCenter (RegisterEventHotKey)
  Selection.swift            Accessibility check; copySelection() sends ⌘C; paste() sends ⌘V; clipboard snapshot/restore
  Claude.swift               model list + streaming client (AsyncThrowingStream<String>)
  Prompts.swift              system/user prompts, tweak instruction, output cleanup, voice-learning prompt
  Diff.swift                 WordDiff (LCS over word/whitespace tokens) + Styled (NSAttributedString for the panel)
  Theme.swift                Lens design tokens: light/dark colors, glass, type metrics (from the UI handoff's CSS)
  Panel.swift                FloatingPanel, PanelController (show/close/replace, key handling, fit-to-content height),
                             PanelModel, PanelView (the Lens design) + small views, ProseView (NSTextView for the text)
  SettingsView.swift         Settings window tabs: General, Modes, Voice, History (+ ShortcutRecorder)
  Store.swift                Mode, HistoryItem, Keychain, Store (all persisted state)
```

## How a cleanup flows

1. `HotKeyCenter` (Carbon) fires → `AppDelegate.trigger()` records the frontmost app as `source`.
2. `Selection.copySelection()` waits for the hotkey's modifiers to be released, posts ⌘C via
   CGEvent, waits for `NSPasteboard.changeCount` to change, reads the string, then restores the
   user's previous clipboard.
3. `PanelController.show()` resets `PanelModel` and shows a **non-activating** `FloatingPanel`.
   The source app stays the active app, which is what makes paste-back work.
4. `PanelModel.start()` streams from `Claude.stream`; `Prompts.clean(_, streaming: true)` strips
   wrapper tags and fences as text arrives.
5. Text streams into the Final view. When it finishes, Final is editable and Changes shows the diff
   (`Styled.diff`); holding "Hold for original" (or Space on it) shows the draft.
6. ⌘↩ → `PanelModel.commit(.replace)` saves a HistoryItem → `PanelController.replace()` closes the
   panel, makes sure the source app is frontmost, then `Selection.paste()` posts ⌘V and restores the clipboard.

## State & persistence (Store.swift)

| What | Where |
| --- | --- |
| API key | Keychain, service `com.tommymassaro.tidy`, account `anthropic-api-key` |
| model, shortcut, voiceProfile, useVoice, restoreClipboard, voiceUpdatedAt | `UserDefaults` (`com.tommymassaro.tidy`) |
| modes, history (max 500) | JSON in `~/Library/Application Support/Tidy/` |

Voice learning: `HistoryItem.edited` is true when what was sent differs from Claude's suggestion.
`Store.learnVoice()` sends recent edited pairs, recent drafts, and optional pasted samples to Claude
and replaces `voiceProfile` with bullet points. When "Match my writing voice" is on, the profile
is appended to every system prompt.

## Conventions

- Keep **zero dependencies** unless there's a strong reason; ask Tommy before adding one.
- UI/state classes are `@MainActor`. Callbacks from C or AppKit that arrive on the main thread but
  aren't annotated (the Carbon handler, `NSEvent` local monitors) hop over with
  `Task { @MainActor in … }` or `MainActor.assumeIsolated { … }`. Never mutate a captured `var`
  from inside a `Task`; declare it inside the task.
- Callback properties are typed `(@MainActor (…) -> Void)?`.
- Panel keyboard shortcuts live in `PanelController.handleKey` (a local key monitor), not in
  SwiftUI `.keyboardShortcut`. Text views swallow Esc and some ⌘ combos, so the monitor is the
  reliable place. Standard editing (⌘C/V/X/A/Z) is also forwarded there with `NSApp.sendAction`.
- SwiftUI views that are created from another file and have `private` state need an explicit `init`
  (see `PanelView`).
- Use AppKit colors (`NSColor.labelColor`, `.systemRed.withAlphaComponent`) in attributed strings
  so they adapt to light/dark mode automatically.
- Copy in the UI is plain and direct. No exclamation marks, no "Oops".
- Model IDs live only in `Claude.models`. Check current IDs at https://docs.claude.com before
  changing them.

## Gotchas

- **Accessibility permission resets on every rebuild.** Ad-hoc signing gives each build a new
  signature, so the old grant goes stale (the toggle stays on but does nothing). `build.sh` runs
  `tccutil reset Accessibility com.tommymassaro.tidy` so macOS asks again cleanly. Re-allow Tidy after each build.
- For the same reason, the **Keychain may ask** "Tidy wants to use confidential information" after a
  rebuild. Choose Always Allow.
- `RegisterEventHotKey` fails if another app already owns the combo (Tommy's old Hammerspoon
  script used ⌥⌘C; it's commented out in `~/.hammerspoon/init.lua`). `Store.hotKeyRegistered`
  drives a warning in Settings.
- ⌘C/⌘V are posted to the physical C and V keys (`kVK_ANSI_*`), which is wrong on non-QWERTY layouts.
- The app has no visible main menu, but `AppDelegate.installMainMenu()` must stay: it's what gives
  text fields their Edit commands.
- Don't make the panel activating. A normal activating window breaks returning focus to the source app.

## Panel design (Lens)

The panel implements the approved **Lens** design (light and dark, subtle glass). The source of truth is
the design handoff package (`Tidy-UI-Claude-Handoff`: `screenshots/lens-*.png`, `source/latest/styles.css`,
`glass-finish.css`). Margin and Compare in that package are alternatives, not built.

- CSS px map 1:1 to points. Colors live only in `Theme`; don't hardcode new ones in views.
- CSS gives text a 1.5x line box; `lineBox(_:)` reproduces it. Without it rows come out short.
- The panel is borderless (24 pt corners, glass in `Glass`), 602 pt wide, and its height follows the
  content (`PanelHeightKey` → `PanelController.fit`), growing downward with the top edge fixed.
- The text is an NSTextView (`ProseView`), not TextEditor, so line height, tracking and the diff's
  rounded highlights (`HighlightLayoutManager`) match the design.
- Reduce Transparency swaps the glass for an opaque surface.
