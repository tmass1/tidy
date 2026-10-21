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
- Panel UI: Spotlight-style non-activating floating panel. The Changes tab is the default view, and Final is the editable text.
- Default modes: Clean up, Fix only, Shorter, Warmer, Polished
- Voice: learned on demand ("Update from N new edits"), not automatically
- The clipboard is restored after copy and after paste (there's a Settings toggle)

## Current status

- All source is written (~1,500 lines) and passes a Swift syntax check (`swiftc -parse`).
- `WordDiff` and `Prompts.clean` were compiled and run on Linux and behave correctly.
- **The app has never been compiled on macOS.** The AppKit and SwiftUI code was written without a
  type checker, so expect a handful of compile errors on the first build.
- Not yet in git. The repo is https://github.com/tmass1/tidy

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

Panel
- [ ] ⌘1–9 switch modes and rerun; the selected chip is highlighted
- [ ] Changes view: deletions struck through in red, insertions in green; readable in light and dark mode
- [ ] Final view is editable; editing shows "edited by you" in the footer
- [ ] Tweak field + ↩ reworks the current result
- [ ] ⌘⇧C copies; ⌘R reruns; ⌘D toggles views; ⌘C/V/X/A/Z work inside the text fields
- [ ] Error states read well: no key, bad key (401), offline, and an empty selection
- [ ] Panel is resizable, draggable by its background, and opens on the screen with the mouse

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
