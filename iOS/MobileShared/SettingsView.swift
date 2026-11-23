import SwiftUI
import UniformTypeIdentifiers
import TidyCore

struct SettingsView: View {
    @ObservedObject var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var editingMode: Mode?
    @State private var importing = false
    @State private var connecting = false
    @State private var startWriting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(store.hasKey ? "Ready to rewrite" : "Connect Tidy", systemImage: store.hasKey ? "checkmark.circle" : "key")
                            .font(.title2.weight(.semibold)).foregroundStyle(Lens.ink)
                        Text(store.hasKey ? "Your Anthropic API key is saved on this iPhone." : "Add your Anthropic API key to rewrite your own text.")
                            .font(.subheadline).foregroundStyle(Lens.muted)
                        Button(store.hasKey ? "Start writing" : "Add API key") {
                            if store.hasKey { store.exitPreview(); dismiss() }
                            else { connecting = true }
                        }.buttonStyle(LensPrimary())
                    }.padding(.vertical, 8)
                    if store.hasKey {
                        Button("Manage connection") { connecting = true }
                    }
                }
                if store.isPreview {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("You’re trying a sample", systemImage: "play.circle").font(.headline)
                            Text("This uses a recorded response. Exit to write your own text.")
                                .font(.subheadline).foregroundStyle(Lens.muted)
                            Button("Exit sample") { store.exitPreview() }.frame(minHeight: 44)
                        }
                    }.listRowBackground(Lens.accentSoft)
                }
                Section("Writing") {
                    Picker("Model", selection: $store.model) {
                        ForEach(Claude.models) { Text($0.name).tag($0.id) }
                    }
                    NavigationLink { modesPage } label: {
                        Label("Manage modes", systemImage: "slider.horizontal.3")
                    }.accessibilityIdentifier("Manage modes")
                    NavigationLink { voicePage } label: {
                        Label("Writing voice", systemImage: "text.quote")
                    }
                }
                Section {
                    NavigationLink { sharingHelp } label: {
                        Label("Use Tidy in other apps", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .accessibilityIdentifier("settingsForm")
            .scrollContentBackground(.hidden).background(Lens.paper)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if persist() { dismiss() } } } }
            .sheet(isPresented: $connecting, onDismiss: { if startWriting { dismiss() } }) {
                ConnectionView(store: store) { startWriting = true; connecting = false }
            }
            .sheet(item: $editingMode) { mode in
                ModeEditor(mode: mode) { edited in
                    if let index = store.modes.firstIndex(where: { $0.id == edited.id }) { store.modes[index] = edited }
                    else { store.modes.append(edited) }
                    persist()
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 0) <= 1_000_000 else { throw ClaudeError(message: "This modes file is too large.") }
                    let imported = try MobileStore.decodeModes(Data(contentsOf: url))
                    var merged = store.modes
                    for mode in imported {
                        if let i = merged.firstIndex(where: { $0.id == mode.id }) { merged[i] = mode }
                        else { merged.append(mode) }
                    }
                    guard merged.count <= 100 else { throw ClaudeError(message: "Keep at most 100 modes. Remove some modes before importing.") }
                    store.modes = merged
                    if persist() { message = "Imported \(imported.count) modes." }
                } catch { message = error.localizedDescription }
            }
            .alert("Settings", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .onChange(of: store.voiceProfile) { _, _ in persist() }
            .onChange(of: store.model) { _, _ in persist() }
            .onChange(of: store.useVoice) { _, _ in persist() }
        }.tint(Lens.accent)
    }
    private var modesPage: some View {
        Form {
            Section {
                ForEach(store.modes) { mode in
                    Button { editingMode = mode } label: {
                        HStack { Text(mode.name).foregroundStyle(Lens.ink); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                    }
                }
                .onDelete { indices in
                    guard store.modes.count - indices.count > 0 else { message = "Keep at least one mode."; return }
                    store.modes.remove(atOffsets: indices)
                    persist()
                }
                Button("Add mode", systemImage: "plus") { editingMode = Mode(name: "", instruction: "") }.disabled(store.modes.count >= 100)
            } footer: { Text("Choose how Tidy rewrites. Swipe left on a mode to delete it.") }
            Section {
                Button("Import Mac modes…", systemImage: "square.and.arrow.down") { importing = true }
            } footer: {
                Text("Choose modes.json from your Mac’s Library/Application Support/Tidy folder. Matching modes are updated; other modes are kept.")
            }
        }.navigationTitle("Modes").scrollContentBackground(.hidden).background(Lens.paper)
    }
    private var voicePage: some View {
        Form {
            Section {
                Toggle("Write in my voice", isOn: $store.useVoice)
                TextField("Your writing voice", text: $store.voiceProfile, axis: .vertical).lineLimit(4...10)
            } footer: {
                Text("Tell Tidy how you like to sound, or paste the voice instructions you use on your Mac.")
            }
        }.navigationTitle("Writing voice").scrollContentBackground(.hidden).background(Lens.paper)
    }
    private var sharingHelp: some View {
        List {
            Section("From another app") {
                Label("Select text and tap Share.", systemImage: "text.cursor")
                Label("Choose Tidy, then a mode.", systemImage: "sparkles")
                Label("Review, copy, and paste it back.", systemImage: "doc.on.doc")
            }
            Section {
                Text("The other app decides whether selected text can be shared. Tidy cannot replace text automatically.")
                Text("Your modes, model and voice settings are shared with the extension on this iPhone. They do not sync with your Mac.")
            }
        }.navigationTitle("Share to Tidy").scrollContentBackground(.hidden).background(Lens.paper)
    }
    @discardableResult private func persist() -> Bool {
        do { try store.save(); return true }
        catch { message = error.localizedDescription; return false }
    }
}

private struct ConnectionView: View {
    @ObservedObject var store: MobileStore
    let onStartWriting: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var key = ""
    @State private var message: String?
    @State private var checking = false
    @State private var keyTask: Task<Void, Never>?
    @State private var replacing = false
    @State private var removeKey = false
    @FocusState private var keyFocused: Bool
    private var connected: Bool { store.hasKey && !replacing }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: connected ? "checkmark.circle" : "key")
                        .font(.largeTitle).foregroundStyle(Lens.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(connected ? "You’re ready to write." : "Connect Tidy.")
                            .font(.largeTitle.weight(.semibold)).tracking(-0.8).foregroundStyle(Lens.ink)
                        Text(connected ? "Your key is saved securely on this iPhone. Return to your draft, choose a mode, and tap Rewrite." : "Use your Anthropic API key, just like on your Mac. No new Tidy account needed.")
                            .font(.body).foregroundStyle(Lens.muted)
                    }
                    if connected {
                        Label("Connected to Anthropic", systemImage: "checkmark.shield")
                            .font(.headline).foregroundStyle(Lens.green).accessibilityIdentifier("connectionReady")
                        Button("Change API key") { replacing = true; message = nil }
                            .frame(minHeight: 44).foregroundStyle(Lens.accent)
                        Button("Remove key", role: .destructive) { removeKey = true }
                            .frame(minHeight: 44).foregroundStyle(Lens.red)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("API key").font(.headline)
                            SecureField("Paste your key", text: $key)
                                .accessibilityLabel("Anthropic API key")
                                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                                .padding(16).background(Lens.well, in: RoundedRectangle(cornerRadius: 14))
                                .focused($keyFocused).submitLabel(.done).onSubmit { if !key.trimmed.isEmpty && !checking { saveKey() } }
                            Text("Stored in the Keychain on this iPhone. Never shown again after saving.")
                                .font(.footnote).foregroundStyle(Lens.muted)
                        }
                        if let message {
                            Label(message, systemImage: "exclamationmark.circle").foregroundStyle(Lens.red)
                                .accessibilityIdentifier("settingsMessage")
                        }
                        Text("Rewriting sends your text and instructions directly to Anthropic. API usage is billed to your Anthropic account.")
                            .font(.footnote).foregroundStyle(Lens.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Lens.paper)
            .safeAreaInset(edge: .bottom) {
                Button(connected ? "Start writing" : (checking ? "Connecting…" : (typeSize.isAccessibilitySize ? "Connect" : "Connect to Anthropic"))) {
                    keyFocused = false
                    if connected { store.exitPreview(); onStartWriting() }
                    else { saveKey() }
                }.buttonStyle(LensPrimary())
                    .accessibilityLabel(connected ? "Start writing" : (checking ? "Connecting…" : "Connect to Anthropic"))
                    .disabled(!connected && (key.trimmed.isEmpty || checking))
                    .opacity(!connected && (key.trimmed.isEmpty || checking) ? 0.5 : 1)
                    .padding(24).background(Lens.paper)
            }
            .navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Remove your API key from this iPhone?", isPresented: $removeKey) {
                Button("Remove key", role: .destructive) {
                    do { try MobileKeychain.write(""); store.hasKey = false; message = nil }
                    catch { message = error.localizedDescription; replacing = true }
                }
            }
            .onDisappear { keyTask?.cancel(); key = "" }
        }.tint(Lens.accent)
    }
    private func saveKey() {
        checking = true; message = nil; keyFocused = false
        let candidate = key.trimmed
        keyTask = Task {
            let result = await Claude.checkKey(candidate)
            guard !Task.isCancelled else { return }
            checking = false
            switch result {
            case .valid:
                do {
                    try MobileKeychain.write(candidate)
                    store.hasKey = true; key = ""; replacing = false
                    store.exitPreview()
                    UIAccessibility.post(notification: .announcement, argument: "Connected. You’re ready to write.")
                } catch { message = error.localizedDescription }
            case .rejected(let text), .unreachable(let text): message = text
            }
        }
    }
}

private struct ModeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var mode: Mode
    let save: (Mode) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $mode.name)
                Section("Instructions") {
                    TextEditor(text: $mode.instruction).frame(minHeight: 220).accessibilityLabel("Mode instructions")
                }
            }
            .navigationTitle(mode.name.isEmpty ? "New mode" : "Edit mode").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(mode); dismiss() }
                    .disabled(mode.name.trimmed.isEmpty || mode.instruction.trimmed.isEmpty || mode.name.count > 80 || mode.instruction.count > 10_000) }
            }
        }
    }
}
