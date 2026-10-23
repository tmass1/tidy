import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

enum SettingsTab: Hashable { case general, modes, voice, history }

/// The Settings window, in the same Lens language as the panel: a glass surface, the wordmark,
/// underline tabs, ruled rows. The panel's "Make it yours." page covers the everyday settings;
/// this window has the rest.
struct SettingsView: View {
    static let size = CGSize(width: 760, height: 620)

    @ObservedObject var store: Store
    var close: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(store: Store, close: @escaping () -> Void = {}) {
        self.store = store
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            tabs
            Group {
                switch store.settingsTab {
                case .general: GeneralTab(store: store)
                case .modes: ModesTab(store: store)
                case .voice: VoiceTab(store: store)
                case .history: HistoryTab(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(1) // the surface's 1 pt border sits inside it, as in the panel
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Glass(reduceTransparency: reduceTransparency))
        .clipShape(RoundedRectangle(cornerRadius: Glass.radius))
        .foregroundStyle(Color(Theme.ink))
        .font(.system(size: 13))
    }

    private var titlebar: some View {
        HStack(spacing: 14) {
            Wordmark()
            Text("Settings")
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.muted))
                .lineBox(12)
                .padding(.leading, 17)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(Theme.rule)).frame(width: 1, height: 18)
                }
                .padding(.leading, 4)
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", label: "Close  ⌘W", size: 13, action: close)
                .accessibilityLabel("Close")
        }
        .padding(.top, 21)
        .padding(.horizontal, 25)
        .padding(.bottom, 14)
        .background(WindowDragArea())
    }

    private var tabs: some View {
        HStack(spacing: 15) {
            tab("General", .general)
            tab("Modes", .modes)
            tab("Voice", .voice)
            tab("History", .history)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.horizontal, 31)
    }

    private func tab(_ title: String, _ value: SettingsTab) -> some View {
        ViewTab(title: title, selected: store.settingsTab == value) { store.settingsTab = value }
    }
}

/// Tab content padding, matching the panel's text area.
private extension View {
    func tabPadding() -> some View {
        padding(EdgeInsets(top: 25, leading: 33, bottom: 26, trailing: 33))
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var store: Store
    @State private var keyDraft = ""
    @State private var trusted = Selection.isTrusted(prompt: false)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
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
            }
            .tabPadding()
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
        .padding(.bottom, 16)
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

struct ModesTab: View {
    @ObservedObject var store: Store
    @State private var selection: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                List {
                    ForEach(Array(store.modes.enumerated()), id: \.element.id) { index, mode in
                        ModeListRow(
                            name: mode.name,
                            shortcut: index < 9 ? "⌘\(index + 1)" : nil,
                            selected: mode.id == selection
                        ) {
                            selection = mode.id
                        }
                        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in store.modes.move(fromOffsets: from, toOffset: to) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                HStack(spacing: 2) {
                    IconButton(symbol: "plus", label: "Add a mode", size: 13, action: addMode)
                    IconButton(symbol: "minus", label: "Remove the selected mode", size: 13, action: removeMode)
                        .disabled(selection == nil || store.modes.count <= 1)
                    Spacer()
                    SmallButton(title: "Reset to defaults") {
                        store.modes = Mode.defaults
                        selection = store.modes.first?.id
                    }
                    .padding(.trailing, -9)
                }
            }
            .frame(width: 220)
            .padding(.trailing, 24)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(Theme.rule)).frame(width: 1)
            }

            if let id = selection, store.modes.contains(where: { $0.id == id }) {
                let mode = binding(for: id)
                VStack(alignment: .leading, spacing: 0) {
                    Caption(text: "Name")
                    LensField(placeholder: "Name", text: mode.name)
                    Caption(text: "What Claude should do")
                        .padding(.top, 22)
                        .padding(.bottom, 7)
                    TextEditor(text: mode.instruction)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 180)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(Theme.layer)))
                    Text("Be specific, for example: “Reply to a client. Confident and warm, under 120 words, end with a clear next step.” Drag modes in the list to reorder; the first one runs by default, and ⌘1–9 switch between them in the panel.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(Theme.muted))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                }
            } else {
                Text("Select a mode to edit it.")
                    .foregroundStyle(Color(Theme.muted))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tabPadding()
        .onAppear {
            if selection == nil { selection = store.modes.first?.id }
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
        selection = mode.id
    }

    private func removeMode() {
        guard let id = selection, store.modes.count > 1,
              let index = store.modes.firstIndex(where: { $0.id == id }) else { return }
        let next = store.modes.indices.contains(index + 1) ? store.modes[index + 1].id : store.modes[max(0, index - 1)].id
        selection = next
        store.modes.remove(at: index)
    }
}

/// A mode in the list: lavender when selected, like the panel's mode strip.
private struct ModeListRow: View {
    let name: String
    let shortcut: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer(minLength: 8)
            if let shortcut {
                Text(shortcut).font(.system(size: 11)).opacity(0.6)
            }
        }
        .lineBox(13)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(Color(selected ? Theme.accent : Theme.ink))
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color(Theme.accentSoft) : hovering ? Color(Theme.layer) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Voice

struct VoiceTab: View {
    @ObservedObject var store: Store
    @State private var samples = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
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
                    .lineSpacing(13 * 0.7 - 3) // CSS line-height 1.7, like the panel's profile
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 6)
                    .padding(.leading, 15)
                    .frame(minHeight: 140)
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
            .tabPadding()
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

struct HistoryTab: View {
    @ObservedObject var store: Store
    @State private var query = ""
    @State private var selection: UUID?

    private var filtered: [HistoryItem] {
        let q = query.trimmed
        guard !q.isEmpty else { return store.history }
        return store.history.filter {
            $0.original.localizedCaseInsensitiveContains(q) || $0.sent.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        if store.history.isEmpty {
            Text("Nothing here yet. Cleanups you replace or copy show up here.")
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.muted))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    LensField(placeholder: "Find something you wrote", text: $query)
                        .padding(.bottom, 8)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filtered) { item in
                                CompactHistoryRow(item: item, selected: item.id == selection) {
                                    selection = item.id
                                }
                            }
                        }
                        .padding(.horizontal, -9) // text lines up with the search field; fills overhang
                    }
                    HStack {
                        Text("\(store.history.count) saved")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(Theme.muted))
                        Spacer()
                        SmallButton(title: "Clear history…", action: confirmClear)
                            .padding(.trailing, -9)
                    }
                    .padding(.top, 8)
                }
                .frame(width: 260)
                .padding(.trailing, 24)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color(Theme.rule)).frame(width: 1)
                }

                if let item = store.history.first(where: { $0.id == selection }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Caption(text: "\(HistoryPage.caption(for: item)) · \(item.mode)")
                            block("Sent", item.sent)
                            if item.edited { block("Claude suggested", item.suggestion) }
                            block("Your draft", item.original)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Select a message.")
                        .foregroundStyle(Color(Theme.muted))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .tabPadding()
        }
    }

    private func block(_ title: String, _ text: String) -> some View {
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
                .font(.system(size: 15))
                .lineSpacing(15 * 0.7 - 3) // CSS line-height 1.7
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 22)
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This removes every saved message. Your voice profile stays."
        let clear = alert.addButton(withTitle: "Clear History")
        clear.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.history = []
            selection = nil
        }
    }
}

/// A history entry in the list: when and where, then the first line.
private struct CompactHistoryRow: View {
    let item: HistoryItem
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HistoryPage.caption(for: item) + (item.edited ? " · edited" : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(Theme.muted))
                    .lineBox(11)
                Text(HistoryPage.titleAndSnippet(item.sent).title)
                    .font(Font(NSFont.systemFont(ofSize: 13, weight: .medium) as CTFont))
                    .lineLimit(1)
                    .lineBox(13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected || hovering ? Color(Theme.layer) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
