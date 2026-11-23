import SwiftUI
import TidyCore

/// One connection lifecycle for setup and Settings. A late check cannot save after leaving.
@MainActor final class KeyConnectionModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var checking = false
    @Published private(set) var saved = false
    @Published private(set) var message: String?
    private var generation = UUID()
    private let check: (String) async -> Claude.KeyCheck
    private let save: (String) throws -> Void
    private var task: Task<Void, Never>?

    init(check: @escaping (String) async -> Claude.KeyCheck, save: @escaping (String) throws -> Void) {
        self.check = check; self.save = save
    }
    func connect() async {
        let candidate = draft.trimmed
        guard !candidate.isEmpty, !checking, !Task.isCancelled else { return }
        let token = UUID(); generation = token
        checking = true; saved = false; message = nil
        let outcome = await check(candidate)
        guard generation == token else { return }
        checking = false
        guard !Task.isCancelled else { return }
        switch outcome {
        case .valid:
            do { try save(candidate); draft = ""; saved = true }
            catch { message = error.localizedDescription }
        case .rejected(let text): message = text
        case .unreachable(let text): message = "Couldn’t check your key. \(text) Try again when you’re online."
        }
    }
    func start() { task?.cancel(); task = Task { await connect() } }
    func cancel() {
        task?.cancel(); task = nil
        generation = UUID(); checking = false; draft = ""; message = nil; saved = false
    }
}

struct KeyConnectionEditor: View {
    @ObservedObject var store: Store
    @ObservedObject private var connection: KeyConnectionModel
    @State private var replacing = false

    init(store: Store) {
        self.store = store
        connection = store.connection
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.hasAPIKey && !replacing {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        StatusDot(text: connection.saved ? "Key checked and saved" : "API key saved")
                        Text("Stored securely in your Mac’s Keychain.")
                            .font(.system(size: 12)).foregroundStyle(Color(Theme.muted)).lineBox(12)
                    }
                    Spacer()
                    SmallButton(title: "Change key") { connection.cancel(); replacing = true }
                }
            } else {
                Text(replacing ? "Replace your API key" : "Connect to Anthropic")
                    .font(.system(size: 13, weight: .medium)).lineBox(13)
                HStack(spacing: 12) {
                    LensField(placeholder: "Paste your Anthropic API key", text: $connection.draft, secure: true, autofocus: true)
                        .onSubmit(connect).disabled(connection.checking)
                    LensButton(title: connection.checking ? "Connecting…" : "Connect", prominent: true, action: connect)
                        .disabled(connection.draft.trimmed.isEmpty || connection.checking)
                }
                if let message = connection.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(Color(Theme.red))
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("connectionError")
                }
                HStack {
                    Link("Get an Anthropic API key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .foregroundStyle(Color(Theme.accent))
                    Spacer()
                    if replacing {
                        SmallButton(title: "Cancel") { connection.cancel(); replacing = false }
                    }
                }.font(.system(size: 12))
                Text("Your text goes directly to Anthropic. API usage is billed to your account.")
                    .font(.system(size: 12)).foregroundStyle(Color(Theme.muted)).lineBox(12)
            }
        }
        .onChange(of: connection.saved) { _, saved in if saved { replacing = false } }
        .onDisappear { connection.cancel() }
    }
    private func connect() {
        guard !connection.checking else { return }
        connection.start()
    }
}

/// Readiness is about selection cleanup; manual pasting can work without Accessibility.
enum SetupReadiness: Equatable {
    case needsKey, needsAccess, needsShortcut, ready
    init(hasKey: Bool, hasAccess: Bool, hasShortcut: Bool) {
        if !hasKey { self = .needsKey }
        else if !hasAccess { self = .needsAccess }
        else if !hasShortcut { self = .needsShortcut }
        else { self = .ready }
    }
    var detail: String {
        switch self {
        case .needsKey: return "Add your Anthropic API key to rewrite your own text."
        case .needsAccess: return "Allow Accessibility to clean up selected text. You can paste a draft into Tidy meanwhile."
        case .needsShortcut: return "Choose an available shortcut to open Tidy from another app."
        case .ready: return "Select text and use your shortcut to begin."
        }
    }
}
