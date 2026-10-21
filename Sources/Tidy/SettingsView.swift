import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

enum SettingsTab: Hashable { case general, modes, voice, history }

struct SettingsView: View {
    @ObservedObject var store: Store

    var body: some View {
        TabView(selection: $store.settingsTab) {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ModesTab(store: store)
                .tabItem { Label("Modes", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.modes)
            VoiceTab(store: store)
                .tabItem { Label("Voice", systemImage: "person.wave.2") }
                .tag(SettingsTab.voice)
            HistoryTab(store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 540)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var store: Store
    @State private var keyDraft = ""
    @State private var trusted = Selection.isTrusted(prompt: false)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Anthropic API key") {
                HStack {
                    SecureField(store.hasAPIKey ? "Saved in your Keychain. Paste a new key to replace it." : "sk-ant-…", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmed.isEmpty)
                }
                HStack(spacing: 6) {
                    Image(systemName: store.hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(store.hasAPIKey ? Color.green : Color.orange)
                    Text(store.hasAPIKey ? "Key saved" : "No key yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("Create a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                .font(.callout)
            }

            Section("Model") {
                Picker("Model", selection: $store.model) {
                    ForEach(Claude.models) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }

            Section("Shortcut") {
                LabeledContent("Clean up selection") {
                    ShortcutRecorder(store: store)
                }
                if !store.hotKeyRegistered {
                    Text("Another app already uses that shortcut (Hammerspoon, maybe). Pick a different one.")
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                }
            }

            Section("Permissions & startup") {
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                    } else {
                        Button("Open System Settings…") { Selection.openAccessibilitySettings() }
                    }
                }
                Toggle("Open Tidy at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in store.setLaunchAtLogin(on) }
                Toggle("Put my clipboard back after pasting", isOn: $store.restoreClipboard)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = Selection.isTrusted(prompt: false)
        }
    }

    private func saveKey() {
        guard !keyDraft.trimmed.isEmpty else { return }
        store.setAPIKey(keyDraft)
        keyDraft = ""
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var store: Store
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(recording ? "Press a shortcut…" : store.shortcut.display)
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 120)
            }
            if recording {
                Text("esc cancels").font(.caption).foregroundStyle(.secondary)
            } else if store.shortcut != .defaultCleanup {
                Button("Reset") { store.shortcut = .defaultCleanup }
                    .buttonStyle(.link)
            }
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
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(Array(store.modes.enumerated()), id: \.element.id) { index, mode in
                        HStack {
                            Text(mode.name)
                            Spacer()
                            if index < 9 {
                                Text("⌘\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(mode.id)
                    }
                    .onMove { from, to in store.modes.move(fromOffsets: from, toOffset: to) }
                }
                Divider()
                HStack(spacing: 4) {
                    Button(action: addMode) { Image(systemName: "plus") }
                        .help("Add a mode")
                    Button(action: removeMode) { Image(systemName: "minus") }
                        .disabled(selection == nil || store.modes.count <= 1)
                        .help("Remove the selected mode")
                    Spacer()
                    Button("Reset to defaults") {
                        store.modes = Mode.defaults
                        selection = store.modes.first?.id
                    }
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 230)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))

            if let id = selection, store.modes.contains(where: { $0.id == id }) {
                let mode = binding(for: id)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.headline)
                    TextField("Name", text: mode.name)
                        .textFieldStyle(.roundedBorder)
                    Text("What Claude should do").font(.headline).padding(.top, 6)
                    TextEditor(text: mode.instruction)
                        .font(.system(size: 13))
                        .padding(6)
                        .frame(minHeight: 160)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    Text("Be specific, for example: “Reply to a client. Confident and warm, under 120 words, end with a clear next step.” Drag modes in the list to reorder; the first one runs by default, and ⌘1–9 switch between them in the panel.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            } else {
                Text("Select a mode to edit it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

// MARK: - Voice

struct VoiceTab: View {
    @ObservedObject var store: Store
    @State private var samples = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Match my writing voice", isOn: $store.useVoice)
            Text("Tidy keeps a short profile of how you write and sends it with every cleanup. It learns from the changes you make to a suggestion before you send it, and from messages you paste below. You can also edit the profile directly.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your voice profile").font(.headline).padding(.top, 4)
            box(TextEditor(text: $store.voiceProfile), minHeight: 140)

            HStack {
                let count = store.editsSinceVoiceUpdate.count
                Button(count == 1 ? "Update from 1 new edit" : "Update from \(count) new edits") {
                    learn(samples: nil)
                }
                .disabled(busy || count == 0 || !store.hasAPIKey)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }

            Text("Or paste a few messages you’ve written").font(.headline).padding(.top, 6)
            box(TextEditor(text: $samples), minHeight: 90)
            Button("Learn from these") { learn(samples: samples) }
                .disabled(busy || samples.trimmed.isEmpty || !store.hasAPIKey)
        }
    }

    private func box<V: View>(_ content: V, minHeight: CGFloat) -> some View {
        content
            .font(.system(size: 13))
            .padding(6)
            .frame(minHeight: minHeight)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
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
    @State private var confirmClear = false

    private var filtered: [HistoryItem] {
        let q = query.trimmed
        guard !q.isEmpty else { return store.history }
        return store.history.filter {
            $0.original.localizedCaseInsensitiveContains(q) || $0.sent.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        if store.history.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.tertiary)
                Text("Nothing here yet").font(.headline)
                Text("Messages you replace or copy from the panel show up here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    TextField("Search", text: $query)
                        .textFieldStyle(.roundedBorder)
                    List(filtered, selection: $selection) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.sent.firstLine).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                if let app = item.app { Text("· \(app)") }
                                if item.edited { Text("· edited") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    HStack {
                        Text("\(store.history.count) saved").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear History…") { confirmClear = true }
                    }
                }
                .frame(width: 280)

                if let item = store.history.first(where: { $0.id == selection }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("\(item.date.formatted(date: .complete, time: .shortened))\(item.app.map { " · \($0)" } ?? "") · \(item.mode)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            block("Sent", item.sent)
                            if item.edited { block("Claude suggested", item.suggestion) }
                            block("Your draft", item.original)
                        }
                        .padding(.trailing, 8)
                    }
                } else {
                    Text("Select a message.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
                Button("Clear History", role: .destructive) {
                    store.history = []
                    selection = nil
                }
            } message: {
                Text("This removes every saved message. Your voice profile stays.")
            }
        }
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.link)
            }
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
