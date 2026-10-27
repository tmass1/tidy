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
bash build.sh            # compile (release, arm64), bundle Tidy.app, sign, install to /Applications, launch
bash release.sh 1.1      # signed + notarized Tidy.zip, tag v1.1, GitHub release (the updater's source)
wrangler deploy          # publish site/ to tidy-app.tommymassaro.com (Cloudflare Worker, custom domain)
swift build              # compile only (fast check while iterating)
tail -50 build.log       # build.sh writes all its output here
log stream --predicate 'process == "Tidy"' --level debug   # runtime logs (NSLog)
```

Requires Apple's command line tools (`xcode-select --install`). Full Xcode isn't required.

## Layout

```
Package.swift
build.sh                     build + bundle + sign (Developer ID if present, else ad-hoc) + install
release.sh                   version bump, notarize, tag, `gh release create` with Tidy.zip
site/                        landing page (static HTML, Lens tokens) at tidy-app.tommymassaro.com
wrangler.jsonc               static-assets Cloudflare Worker serving site/; `wrangler deploy` publishes it
Resources/Info.plist         LSUIElement=true (no Dock icon), bundle id com.tommymassaro.tidy
Resources/AppIcon.png        1024px source; build.sh turns it into AppIcon.icns with sips/iconutil
Sources/Tidy/
  TidyApp.swift              @main entry, String helpers (trimmed, wordCount, firstLine)
  AppDelegate.swift          status item + menu, hotkey → trigger(), showSettings → the panel, hidden Edit menu
  HotKey.swift               Shortcut model (Carbon keycodes/modifiers) + HotKeyCenter (RegisterEventHotKey)
  Selection.swift            Accessibility check; copySelection() sends ⌘C; paste() sends ⌘V; clipboard snapshot/restore
  Claude.swift               model list + streaming client (AsyncThrowingStream<String>)
  Prompts.swift              system/user prompts, tweak instruction, output cleanup, voice-learning prompt
  Diff.swift                 WordDiff (LCS over word/whitespace tokens) + Styled (NSAttributedString for the panel)
  Theme.swift                Lens design tokens: light/dark colors, glass, type metrics (from the UI handoff's CSS)
  Panel.swift                FloatingPanel, PanelController (show/close/replace, key handling, fit-to-content height),
                             PanelModel, PanelView (the Lens design) + small views, ProseView (NSTextView for the text)
  PanelPages.swift           The panel's tabbed Settings page + shared Lens parts (SettingRow, LensField, LensButton…)
  SettingsView.swift         The Settings tabs: General, Modes, Voice, History (+ ShortcutRecorder, UpdatesRow)
  Store.swift                Mode, HistoryItem, Keychain, Store (all persisted state)
  Updater.swift              checks GitHub's latest release daily, downloads Tidy.zip, verifies team Y5V8Y3BH9A, swaps + relaunches
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
   (`Styled.diff`); holding "Original" (or Space on it) shows the draft. Anything typed in the tray's
   one field reworks the version showing and adds a step to the trail (`PanelModel.steps`).
6. ⌘↩ → `PanelModel.commit(.replace)` saves a HistoryItem → `PanelController.replace()` closes the
   panel, makes sure the source app is frontmost, then `Selection.paste()` posts ⌘V and restores the clipboard.

## State & persistence (Store.swift)

| What | Where |
| --- | --- |
| API key | Keychain, service `com.tommymassaro.tidy`, account `anthropic-api-key` |
| model, shortcut, voiceProfile, useVoice, learnFromEdits, restoreClipboard, voiceUpdatedAt, charLimits | `UserDefaults` (`com.tommymassaro.tidy`) |
| modes, history (max 500) | JSON in `~/Library/Application Support/Tidy/` |

Voice learning: `HistoryItem.edited` is true when what was sent differs from Claude's suggestion.
`Store.learnVoice()` sends recent edited pairs, recent drafts, and optional pasted samples to Claude
and replaces `voiceProfile` with bullet points. It runs on demand (Settings › Voice) or, when
"Learn my writing style" (`learnFromEdits`) is on, by itself after three new edited sends. When
"Write in my voice" (`useVoice`) is on, the profile is appended to every system prompt.

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

- **Signing:** `build.sh` signs with Tommy's "Developer ID Application: Thomas Massaro (Y5V8Y3BH9A)",
  so the Accessibility grant and Keychain access survive rebuilds. On a Mac without that certificate it
  falls back to ad-hoc signing, which gives every build a new signature; then it runs
  `tccutil reset Accessibility com.tommymassaro.tidy` so macOS asks again cleanly.
- The repo is **public** (github.com/tmass1/tidy). Don't commit keys, personal data or private notes.
- Notarization needs a keychain profile named `tidy-notary` (see the top of `release.sh`); only Tommy can create it.
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
- **All settings live in the panel**, on one Settings page with tabs: General, Modes, Voice, History
  (`PanelModel.page == .settings`, tab in `Store.settingsTab`). There is no separate Settings window.
  The sliders icon opens General, the clock icon opens History, and either toggles back to the text.
  The menu bar's Settings… / History… / Check for Updates…, ⌘, and first launch (no API key) all call
  `PanelController.showSettings`, which opens the panel there. Esc steps back (history entry → list →
  text → closed). There's no mock for the tabs, so they're built from the panel's parts (`SettingRow`,
  `CheckboxRow`, `LensField`, `LensButton`, `SmallButton`). Modes and History drill in (list → item) to
  fit the 602 pt width. Clicking outside the panel doesn't close it while Settings is showing.
- **Control tray** (the bottom of the editor): mode chips stay on their own row above it; inside it are
  the trail of steps (only once there's a change), the one text field (`Theme.well`), and the status line
  with Replace. A mode run starts a new trail; each typed change adds a step built on the version showing
  (`PanelModel.record`); clicking a step goes back to it (`goToStep`) and later steps drop off on the next
  change; the bookmark saves the steps up to the current one as a mode (`saveStepsAsMode`). Trails longer
  than five collapse to first › … › last three. This came from the "V4" mock on the design canvas.
- Character limit: click the count in the status line to set "Max characters" for the current app
  (`Store.charLimits`, keyed by bundle id). With a limit the count reads "164 / 300 characters" (red when
  over), `Prompts.user` tells Claude it's a hard limit, and setting a limit below the current result
  reruns it. Esc cancels the field.
- `HighlightLayoutManager` only tightens backgrounds that come from the text's own `.backgroundColor`
  (the diff). Text selection must stay a normal contiguous block.
- Closing: Esc, ⌘W, ⌥⌘C again, the × in the title bar, or a click anywhere outside the panel (a
  global mouse monitor, installed only while the panel is open). The × isn't in the Lens mock; it
  was added at Tommy's request.

## Landing page (keep it in step with the app)

- `site/index.html` is **light only** (no dark-mode styles), except the footer (`.site-foot`), which uses the
  app's dark `Theme` colors scoped to itself and links to Tidy UI and tommymassaro.com. Headlines use Newsreader, self-hosted in
  `site/assets/fonts/` (OFL); everything else is the system font, like the app. The page makes no
  third-party requests.
- The hero (`.demo`) is a hand-built HTML copy of the panel, animated by a small inline script: select a
  draft, ⌥⌘C, the cleanup streams in, Changes, a typed change with the trail, ⌘↩ replaces. Its colors
  are the `Theme` tokens (light) copied into the page's `:root`; its metrics come from `Panel.swift`.
  The captions under it (`.steps-live`) light up from the demo's `phase` events, so a new or reordered
  step in the script needs its caption updated too.
  The six "details" cards each show a small looping copy of part of the app (the trail and field, the voice
  profile, the character-limit meter, History search, Original, the menu bar menu in its real item order); they
  are pure CSS keyframes that run only while on screen.
  Other sections also echo the app: the mode names and ⌘ numbers, the diff colors, "Ready to replace ·
  N words", the trail, the Original button, the menu bar's "Update to Tidy X…".
- **Any change to the panel's UI or copy updates the site in the same change.** That covers layout,
  tokens, labels, placeholders, status lines and modes in `Panel.swift`, `PanelPages.swift`, `Theme.swift`
  and `Store.swift`. Update the demo's markup, styles and script and the sections that echo the app,
  re-render `assets/hero-light.png` (the og:image), then `wrangler deploy`.
- With reduced motion (or no JavaScript) the demo shows its static finished frame, so the markup's
  default state must stay a complete, correct panel.
