import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

/// The tabs of the panel's Settings page (see SettingsPage in PanelPages.swift).
enum SettingsTab: Hashable { case general, modes, voice, history }

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var store: Store
    var onSetup: @MainActor () -> Void = {}
    @State private var keyDraft = ""
    @State private var trusted = Selection.isTrusted(prompt: false)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            apiKey
            SettingRow(title: "Writing model", detail: "Use for your next cleanup.") {
                ModelMenu(store: store)
            }
            SettingRow(
                title: "Clean up selection",
                detail: store.hotKeyRegistered
                    ? "Select your text, then press the shortcut."
                    : "Another app already uses that shortcut (Hammerspoon, maybe). Pick a different one.",
                detailIsError: !store.hotKeyRegistered
            ) {
                ShortcutRecorder(store: store)
            }
            SettingRow(title: "Accessibility") {
                if trusted {
                    StatusDot(text: "Allowed")
                } else {
                    LensButton(title: "Open System Settings…") { Selection.openAccessibilitySettings() }
                }
            }
            CheckboxRow(title: "Open Tidy at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in store.setLaunchAtLogin(on) }
            CheckboxRow(title: "Put my clipboard back after pasting", isOn: $store.restoreClipboard)
            UpdatesRow(updater: Updater.shared)
            SettingRow(title: "Setup", detail: "Go through the key, Accessibility, shortcut and a practice run again.") {
                LensButton(title: "Run setup") { onSetup() }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = Selection.isTrusted(prompt: false)
        }
    }

    private var apiKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Anthropic API key").lineBox(13)
                Text(store.hasAPIKey ? "Saved in your Keychain. Paste a new key to replace it." : "No key yet")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(Theme.muted))
                    .lineBox(12)
            }
            HStack(alignment: .center, spacing: 12) {
                LensField(placeholder: store.hasAPIKey ? "Paste a new key" : "sk-ant-…", text: $keyDraft, secure: true)
                    .onSubmit(saveKey)
                LensButton(title: "Save", prominent: true, action: saveKey)
                    .disabled(keyDraft.trimmed.isEmpty)
            }
            HStack {
                if store.hasAPIKey {
                    StatusDot(text: "Key saved")
                } else {
                    StatusDot(text: "No key yet", isError: true)
                }
                Spacer()
                Link("Create a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(Theme.accent))
            }
        }
        .padding(.vertical, 16)
        .padding(.bottom, 1)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func saveKey() {
        guard !keyDraft.trimmed.isEmpty else { return }
        store.setAPIKey(keyDraft)
        keyDraft = ""
    }
}

/// "Tidy 1.0 · Up to date", with Check for updates or Update and relaunch.
struct UpdatesRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        SettingRow(title: "Tidy \(updater.currentVersion)", detail: detail, detailIsError: isError) {
            switch updater.state {
            case .available:
                LensButton(title: "Update and relaunch", prominent: true) { Task { await updater.install() } }
            case .checking, .installing:
                ProgressView().controlSize(.small)
            default:
                LensButton(title: "Check for updates") { Task { await updater.check() } }
            }
        }
    }

    private var detail: String {
        switch updater.state {
        case .idle: "Updates come from GitHub."
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .available(let release): "Tidy \(release.version) is available."
        case .installing: "Downloading the update…"
        case .failed(let message): message
        }
    }

    private var isError: Bool {
        if case .failed = updater.state { return true }
        return false
    }
}

/// The status line's small dot and text, as in the panel's footer.
struct StatusDot: View {
    let text: String
    var isError = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(isError ? Theme.red : Theme.green))
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(isError ? Theme.red : Theme.muted))
                .lineBox(12)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var store: Store
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if recording {
                Text("esc cancels")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(Theme.muted))
            } else if store.shortcut != .defaultCleanup {
                SmallButton(title: "Reset") { store.shortcut = .defaultCleanup }
            }
            Button(action: toggle) {
                Text(recording ? "Press a shortcut…" : store.shortcut.display)
                    .font(.system(size: 13, weight: .medium))
                    .lineBox(13)
                    .frame(minWidth: 110)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color(recording ? Theme.accent : Theme.ink))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(recording ? Theme.accentSoft : Theme.layer))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(BareButtonStyle())
            .help("Click, then press the new shortcut")
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        if recording { stop() } else { start() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                handle(event)
            }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard recording else { return false }
        if event.keyCode == UInt16(kVK_Escape) {
            stop()
            return true
        }
        if let shortcut = Shortcut(event: event) {
            store.shortcut = shortcut
            stop()
        } else {
            NSSound.beep()
        }
        return true
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        store.registerHotKey()
    }
}

// MARK: - Modes

/// A list of modes; click one to edit it. Drag to reorder.
struct ModesTab: View {
    @ObservedObject var store: Store
    @State private var editing: UUID?

    private static let rowHeight: CGFloat = 33

    var body: some View {
        if let id = editing, store.modes.contains(where: { $0.id == id }) {
            editor(binding(for: id))
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(Array(store.modes.enumerated()), id: \.element.id) { index, mode in
                    ModeListRow(name: mode.name, shortcut: index < 9 ? "⌘\(index + 1)" : nil) {
                        editing = mode.id
                    }
                    .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { from, to in store.modes.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(store.modes.count) * Self.rowHeight + 8)
            .padding(.horizontal, -17) // row text lines up with the page (row padding 9 + the list's own 8)
            .padding(.top, 12)

            Text("Drag to reorder. The first mode runs by default, and ⌘1–9 switch between them.")
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.muted))
                .fixedSize(horizontal: false, vertical: true)
                .lineBox(12)
                .padding(.top, 8)
            HStack {
                SmallButton(title: "Add a mode", symbol: "plus") { addMode() }
                Spacer()
                SmallButton(title: "Reset to defaults") { store.modes = Mode.defaults }
            }
            .padding(.horizontal, -9)
            .padding(.top, 10)
        }
    }

    private func editor(_ mode: Binding<Mode>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallButton(title: "‹ All modes") { editing = nil }
                .padding(.leading, -9)
                .padding(.top, 10)
            Caption(text: "Name").padding(.top, 14)
            LensField(placeholder: "Name", text: mode.name)
            Caption(text: "What Claude should do")
                .padding(.top, 22)
                .padding(.bottom, 7)
            TextEditor(text: mode.instruction)
                .font(.system(size: 13))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 160)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(Theme.layer)))
            Text("Be specific, for example: “Reply to a client. Confident and warm, under 120 words, end with a clear next step.”")
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.muted))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            HStack {
                Spacer()
                SmallButton(title: "Delete mode", destructive: true) { remove(mode.wrappedValue.id) }
                    .disabled(store.modes.count <= 1)
            }
            .padding(.trailing, -9)
            .padding(.top, 12)
        }
    }

    private func binding(for id: UUID) -> Binding<Mode> {
        Binding(
            get: { store.modes.first(where: { $0.id == id }) ?? Mode(name: "", instruction: "") },
            set: { newValue in
                if let i = store.modes.firstIndex(where: { $0.id == id }) { store.modes[i] = newValue }
            }
        )
    }

    private func addMode() {
        let mode = Mode(name: "New mode", instruction: "Describe how the message should be rewritten.")
        store.modes.append(mode)
        editing = mode.id
    }

    private func remove(_ id: UUID) {
        guard store.modes.count > 1 else { return }
        store.modes.removeAll { $0.id == id }
        editing = nil
    }
}

/// A mode in the list: its name, ⌘ number and a chevron to edit it.
private struct ModeListRow: View {
    let name: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(name).lineLimit(1)
            Spacer(minLength: 8)
            if let shortcut {
                Text(shortcut).font(.system(size: 11)).opacity(0.6)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(Theme.muted))
        }
        .lineBox(13)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color(Theme.layer) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edit this mode")
    }
}

// MARK: - Voice

struct VoiceTab: View {
    @ObservedObject var store: Store
    @State private var samples = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CheckboxRow(
                title: "Write in my voice", detail: "Use my style profile in new cleanups.",
                isOn: $store.useVoice
            )
            CheckboxRow(
                title: "Learn my writing style", detail: "Notice the edits I make before replacing.",
                isOn: $store.learnFromEdits
            )
            Text("Tidy keeps a short profile of how you write and sends it with every cleanup. It learns from the changes you make to a suggestion before you send it, and from messages you paste below. You can also edit the profile directly.")
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.muted))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Caption(text: "Your voice profile")
                .padding(.top, 22)
                .padding(.bottom, 7)
            TextEditor(text: $store.voiceProfile)
                .font(.system(size: 13))
                .lineSpacing(13 * 0.7 - 3) // CSS line-height 1.7
                .scrollContentBackground(.hidden)
                .padding(.vertical, 6)
                .padding(.leading, 15)
                .frame(minHeight: 120)
                .background(Color(Theme.popover))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(Theme.accent)).frame(width: 2)
                }

            HStack(spacing: 10) {
                let count = store.editsSinceVoiceUpdate.count
                LensButton(title: count == 1 ? "Update from 1 new edit" : "Update from \(count) new edits") {
                    learn(samples: nil)
                }
                .disabled(busy || count == 0 || !store.hasAPIKey)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                if let message {
                    Text(message).font(.system(size: 12)).foregroundStyle(Color(Theme.muted))
                }
            }
            .padding(.top, 12)

            Caption(text: "Or paste a few messages you’ve written")
                .padding(.top, 26)
                .padding(.bottom, 7)
            TextEditor(text: $samples)
                .font(.system(size: 13))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 90)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(Theme.layer)))
            LensButton(title: "Learn from these") { learn(samples: samples) }
                .disabled(busy || samples.trimmed.isEmpty || !store.hasAPIKey)
                .padding(.top, 12)
        }
    }

    private func learn(samples pasted: String?) {
        busy = true
        message = nil
        Task { @MainActor in
            do {
                try await store.learnVoice(samples: pasted)
                message = "Profile updated."
                if pasted != nil { samples = "" }
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - History

/// Search, a list of entries, and each entry's sent text, Claude's suggestion and your draft.
struct HistoryTab: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @State private var search = ""
    @State private var confirmingClear = false

    var body: some View {
        if let id = model.historySelection, let item = store.history.first(where: { $0.id == id }) {
            detail(item)
        } else {
            list
        }
    }

    private var matches: [HistoryItem] {
        let term = search.trimmed.lowercased()
        guard !term.isEmpty else { return store.history }
        return store.history.filter {
            "\($0.sent) \($0.original) \($0.app ?? "")".lowercased().contains(term)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            LensField(placeholder: "Find something you wrote", text: $search)
                .padding(.top, 10)
                .padding(.bottom, 4)
            let items = matches
            if items.isEmpty {
                Text(store.history.isEmpty
                     ? "Nothing here yet. Cleanups you replace or copy show up here."
                     : "No matching cleanups.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(Theme.muted))
                    .lineBox(12)
                    .padding(.top, 14)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        HistoryRow(item: item) { model.historySelection = item.id }
                    }
                }
            }
            if !store.history.isEmpty {
                clearRow.padding(.top, 14)
            }
        }
    }

    /// "23 saved · Clear history…", which asks inline before clearing.
    private var clearRow: some View {
        HStack(spacing: 4) {
            if confirmingClear {
                Text("Clear all \(store.history.count)? Your voice profile stays.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(Theme.muted))
                Spacer()
                SmallButton(title: "Cancel") { confirmingClear = false }
                SmallButton(title: "Clear history", destructive: true) {
                    store.history = []
                    confirmingClear = false
                }
                .padding(.trailing, -9)
            } else {
                Text("\(store.history.count) saved")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(Theme.muted))
                Spacer()
                SmallButton(title: "Clear history…") { confirmingClear = true }
                    .padding(.trailing, -9)
            }
        }
    }

    private func detail(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallButton(title: "‹ All history") { model.historySelection = nil }
                .padding(.leading, -9)
                .padding(.top, 10)
            Caption(text: "\(HistoryText.caption(for: item)) · \(item.mode)")
                .padding(.top, 14)
            block("Sent", item.sent, size: 17)
            if item.edited { block("Claude suggested", item.suggestion, size: 14) }
            block("Your draft", item.original, size: 14)
        }
    }

    private func block(_ title: String, _ text: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Caption(text: title)
                Spacer()
                SmallButton(title: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .padding(.trailing, -9)
            }
            Text(text)
                .font(.system(size: size))
                .lineSpacing(size * 0.7 - 3) // CSS line-height 1.7
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 18)
    }
}
