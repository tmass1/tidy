# Handoff: Tidy

_Written October 21, 2026, at the end of the planning and first-draft session in Claude chat._

## Why this exists

Tommy constantly pastes emails and texts into Claude or ChatGPT with "clean up this message", which
means a throwaway chat each time and a lot of switching back and forth. The first attempt was a
Hammerspoon script (`~/.hammerspoon/cleanup.lua`). He wanted something better because of:

- setup friction and the Hammerspoon dependency
- a hotkey that didn't trigger reliably
- a UI that didn't feel polished enough
- speed (the Claude Code CLI took seconds to start on every run)

## Decisions already made (by Tommy)

| Topic | Decision |
| --- | --- |
| Form | Native macOS menu bar app, Swift, no Dock icon |
| Engine | Anthropic API key, streaming (not the CLI, no Ollama for now) |
| Default hotkey | ⌥⌘C, changeable in Settings |
| Default model | Sonnet 5.5 (`claude-sonnet-5-5`); Haiku 5.5 and Opus 5.5 selectable |
| Features | Streaming + inline word diff, custom modes, searchable history, learns his writing voice |

Defaults chosen during implementation, all open to change:
- Panel UI: Spotlight-style non-activating floating panel in the **Lens** design (see CLAUDE.md, Panel design). Final is the default view and is editable; Changes shows the diff.
- Default modes: Clean up, Fix only, Shorter, Warmer, Polished
- Voice: learned on demand ("Update from N new edits"), not automatically
- The clipboard is restored after copy and after paste (there's a Settings toggle)

## Current status

_Updated October 21, 2026._

- All source is written (~2,000 lines across 10 files) and is in git at https://github.com/tmass1/tidy.
- **Compiles on macOS** (Apple Swift 6.4 toolchain, Swift 5 language mode) with zero errors and zero
  warnings, debug and release. No compile fixes were needed.
- `bash build.sh` bundles, signs, installs and launches Tidy.app; it runs in the menu bar.
- The copy/paste path logs to NSLog (`Tidy: triggered from…`, `copy changed the pasteboard after…`,
  `pasting into…`) so missed selections and wrong-app pastes can be diagnosed from `log stream`.
- **The panel is now the Lens design** (approved UI handoff), in light and dark with subtle glass.
  Rendered offscreen and compared with `lens-light.png` / `lens-dark.png`: the wordmark, tabs and first
  text line land on the same pixels; the lower rows are within 2-4 pt. Checked: Final, Changes
  (multi-paragraph diff), hold for original, streaming, empty draft, error, long text (caps and scrolls),
  short text, another mode selected. Not yet checked on screen: glass over a real desktop, corners and
  shadow, dragging, keyboard focus, the hold gesture, Reduce Transparency.
- History and Settings are pages inside the panel, as in the Lens design (rendered and checked in
  light and dark: list, entry, empty, settings with and without a voice profile). "Learn my writing
  style" is a new setting: when on, three new edited sends update the voice profile automatically.
  The page adds an "All settings…" link to the Settings window, which isn't in the mock.
- The Settings window now matches the panel (glass, wordmark, underline tabs, ruled rows, lavender
  checkboxes). No mock exists for it; it reuses the panel's components. Rendered in light and dark.
  The panel closes on a × or a click outside it, as Tommy asked.
- **Core-loop QA hasn't started.** Nothing in the QA checklist below has been verified on a Mac yet.

## First tasks, in order

1. **Make it compile.** Run `bash build.sh` and fix errors from `build.log`. Keep fixes minimal and
   in the spirit of the existing code. Areas most likely to need a nudge:
   - `MainActor.assumeIsolated` closures in `PanelController.installKeyMonitor` and
     `ShortcutRecorder.start` (they capture a non-Sendable `NSEvent`)
   - the Carbon `InstallEventHandler` closure in `HotKey.swift` (must stay a capture-free C function pointer)
   - `NSApp.activate()` / `NSRunningApplication.activate(options:)` / API availability on macOS 14
   - `@ViewBuilder` bodies with `let` declarations (`ModesTab`, `VoiceTab`)
2. **Make the core loop work end to end** (QA checklist below), in Mail, Messages, Slack, Chrome
   (Gmail) and Notes. This is the part that failed with Hammerspoon, so it matters most.
3. **Check the model IDs** in `Claude.models` against https://docs.claude.com.
4. **Add a test target** for the pure-Swift logic (`WordDiff`, `Prompts.clean`, `Shortcut.display`,
   `HistoryItem.edited`) if XCTest or Swift Testing is available with the command line tools.
5. Commit and push to `tmass1/tidy`, with a `.gitignore` for `.build/`, `build/`, `build.log`, `.DS_Store`, `.swiftpm/`.

## QA checklist

Core loop
- [ ] App launches into the menu bar (wand icon), no Dock icon; Settings opens on first launch with no key
- [ ] Saving an API key shows "Key saved"; it survives a relaunch
- [ ] Accessibility prompt appears; the General tab shows "Allowed" once granted
- [ ] Select text in Mail, then ⌥⌘C: the panel appears over Mail, and text streams within about a second
- [ ] Chrome doesn't open DevTools on ⌥⌘C (the hotkey wins)
- [ ] ⌘↩ replaces the selection in Mail, Messages, Slack, Gmail in Chrome, and Notes
- [ ] The clipboard afterwards holds whatever was on it before Tidy ran
- [ ] With nothing selected, ⌥⌘C opens an empty panel; ⌘V into the draft starts a cleanup automatically
- [ ] Esc closes and focus returns to the source app; ⌥⌘C while the panel is open closes it
- [ ] Selecting text in Final or Changes shows one solid highlight, not separate bars per line
- [ ] Character limit: click the count, set 160 in Messages, ↩; the next cleanup stays under it; the count turns red if your edits go over; Clear removes it; another app keeps its own limit
- [ ] The × in the title bar closes it; so does clicking anywhere outside the panel (and the source app keeps focus)

Panel
- [ ] ⌘1–9 switch modes and rerun; the selected mode is lavender and shows its ⌘ number
- [ ] Changes view: deletions struck through in red, insertions in green; readable in light and dark mode
- [ ] Final is the default view and is editable; the word count follows edits; Tab moves to the refine field
- [ ] Hold for original (mouse, or Space when focused) shows the draft and releases back without the panel jumping
- [ ] Tweak field + ↩ reworks the current result
- [ ] ⌘⇧C copies; ⌘R reruns; ⌘D toggles views; ⌘C/V/X/A/Z work inside the text fields
- [ ] Error states read well: no key, bad key (401), offline, and an empty selection
- [ ] Panel fits its text (grows downward, long text scrolls), drags by its title bar, opens on the screen with the mouse
- [ ] Glass reads well over light and dark desktops; corners and shadow look right; Reduce Transparency gives an opaque panel
- [ ] History page: search filters as you type, an entry opens and its text can be copied, Esc goes back a step
- [ ] Settings page: the model menu changes the model used next; both checkboxes persist after relaunch; "All settings…" opens the window
- [ ] With "Learn my writing style" on, three edited sends update the voice profile on their own

Settings
- [ ] Shortcut recorder: record ⌃⌥C, then it works globally; Esc cancels recording; Reset restores ⌥⌘C
- [ ] Modes: add, rename, edit, delete, drag to reorder, Reset to defaults; changes show in the panel right away
- [ ] Voice: after two or three edited sends, "Update from N new edits" produces bullet points; "Learn from these" works with pasted samples
- [ ] History: entries appear after Replace/Copy, search filters, Copy buttons work, Clear asks first
- [ ] Open at login toggles (check System Settings › General › Login Items)

## Known risks / things to watch

- **Focus return after paste**: replace relies on the source app still being active (the panel is
  non-activating). If the user clicked elsewhere, `replace()` tries `app.activate(options: [])`,
  which macOS 14's cooperative activation may refuse. Confirm it works, or find a better approach.
- **⌘C timing**: `copySelection()` polls the pasteboard for up to ~600 ms. Electron apps or a
  busy browser may need longer; if selections are missed, tune it before redesigning anything.
- **SwiftUI in a non-activating panel**: TextEditor focus and caret need checking. `focusForOpen()`
  focuses the draft field only when it's empty.
- **Window chrome**: titled + fullSizeContentView + clear background + NSVisualEffectView. Check
  that the corners and translucency look right on macOS 26.
- **Ad-hoc signing friction** (see CLAUDE.md, Gotchas). The likely fix is a stable self-signed
  code-signing identity created once by a script, so the Accessibility and Keychain grants survive rebuilds.

## Backlog (not started; check with Tommy before building)

- Stable signing identity (above). This is the biggest quality-of-life fix for development.
- Menu bar icon state while streaming; a small toast after "Copied"
- Remember the last mode per app (e.g. Messages → Shorter)
- "Instant" variant: a second hotkey that replaces in place with no panel
- Use AX `kAXSelectedTextAttribute` first and fall back to ⌘C, so the clipboard isn't touched when possible
- Keyboard-layout-aware ⌘C/⌘V (look up the keycode for "c"/"v" in the current layout)
- Prompt caching for the system prompt and voice profile
- Export/import modes; sync history via iCloud Drive

## Related files outside the repo

- `~/.hammerspoon/cleanup.lua`: the original Hammerspoon version. Its `require` line in
  `~/.hammerspoon/init.lua` is commented out so it doesn't take ⌥⌘C.
