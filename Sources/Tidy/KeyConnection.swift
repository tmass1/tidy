import SwiftUI
import TidyCore

/// One connection lifecycle for setup and Settings. A late check cannot save after leaving.
@MainActor final class KeyConnectionModel: ObservableObject {
    @Published var draft = ""
    /// The AI the key being entered is for. It becomes the one in use only when the key connects.
    @Published private(set) var provider: AIProvider
    @Published private(set) var checking = false
    @Published private(set) var saved = false
    @Published private(set) var message: String?
    private var generation = UUID()
    private let check: (String, AIProvider) async -> Claude.KeyCheck
    private let save: (String, AIProvider) throws -> Void
    private var task: Task<Void, Never>?

    init(provider: AIProvider = .claude,
         check: @escaping (String, AIProvider) async -> Claude.KeyCheck,
         save: @escaping (String, AIProvider) throws -> Void) {
        self.provider = provider; self.check = check; self.save = save
    }
    /// Picks which AI the key is for. Not while a key is being checked.
    func choose(_ provider: AIProvider) {
        guard !checking, provider != self.provider else { return }
        self.provider = provider
        message = nil; saved = false
    }
    func connect() async {
        let candidate = draft.trimmed
        let chosen = provider
        guard !candidate.isEmpty, !checking, !Task.isCancelled else { return }
        let token = UUID(); generation = token
        checking = true; saved = false; message = nil
        let outcome = await check(candidate, chosen)
        guard generation == token else { return }
        checking = false
        guard !Task.isCancelled else { return }
        switch outcome {
        case .valid:
            do { try save(candidate, chosen); draft = ""; saved = true }
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

/// "Your AI": the one in use, and the place to pick one and add its key. Tidy uses one AI at a
/// time, so connecting a different one replaces it. Shared by Settings and setup's first step.
struct KeyConnectionEditor: View {
    @ObservedObject var store: Store
    /// Settings shows the "Your AI" heading before there's a key; setup's own title covers it.
    var showsTitle = true
    @ObservedObject private var connection: KeyConnectionModel
    @State private var replacing = false

    /// `changing` opens it on the list, as after pressing Change (for previews and tests).
    init(store: Store, showsTitle: Bool = true, changing: Bool = false) {
        self.store = store
        self.showsTitle = showsTitle
        connection = store.connection
        _replacing = State(initialValue: changing)
    }

    private var choosing: Bool { !store.hasAPIKey || replacing }
    private var chosen: AIProvider { connection.provider }
    /// Entering a new key for the AI already in use, not switching.
    private var sameAI: Bool { store.hasAPIKey && chosen == store.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.hasAPIKey {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your AI").lineBox(13)
                        Text("\(store.provider.keyName) saved in your Mac’s Keychain.")
                            .font(.system(size: 12)).foregroundStyle(Color(Theme.muted)).lineBox(12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StatusDot(text: "\(store.provider.name) connected")
                    if !replacing {
                        LensButton(title: "Change") { connection.cancel(); connection.choose(store.provider); replacing = true }
                            .accessibilityLabel("Change your AI or its key")
                    }
                }
            } else if showsTitle {
                Text("Your AI").lineBox(13)
            }
            if choosing {
                chooser.padding(.top, store.hasAPIKey ? 16 : showsTitle ? 4 : 0)
            }
        }
        .onAppear { if !connection.checking { connection.choose(store.provider) } }
        .onChange(of: connection.saved) { _, saved in if saved { replacing = false } }
        .onDisappear { connection.cancel() }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.hasAPIKey || showsTitle {
                Text("Tidy uses one AI at a time. Pick one and add its key.")
                    .font(.system(size: 12)).foregroundStyle(Color(Theme.muted)).lineBox(12)
            }
            VStack(spacing: 0) {
                ForEach(Array(AIProvider.allCases.enumerated()), id: \.element) { index, provider in
                    if index > 0 { Rectangle().fill(Color(Theme.wellBorder)).frame(height: 1) }
                    choice(provider)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(Theme.wellBorder)))
            .disabled(connection.checking)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("AI")

            HStack(spacing: 12) {
                LensField(placeholder: sameAI ? "Paste a new \(chosen.keyName)" : "Paste \(chosen.aKey)",
                          text: $connection.draft, secure: true, autofocus: true)
                    .onSubmit(connect).disabled(connection.checking)
                LensButton(title: connection.checking ? "Connecting…" : "Connect", prominent: true, action: connect)
                    .disabled(connection.draft.trimmed.isEmpty || connection.checking)
            }
            if let message = connection.message {
                Text(store.hasAPIKey && !sameAI ? "\(message) Tidy is still using \(store.provider.name)." : message)
                    .font(.system(size: 12)).foregroundStyle(Color(Theme.red))
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("connectionError")
            }
            if chosen == .gemini { freeTierNotice }
            HStack {
                Link("Get \(chosen.aKey)", destination: chosen.keysURL)
                    .foregroundStyle(Color(Theme.accent))
                Spacer()
                if replacing {
                    SmallButton(title: "Cancel") { connection.cancel(); connection.choose(store.provider); replacing = false }
                }
            }.font(.system(size: 12))
            Text(footnote)
                .font(.system(size: 12)).foregroundStyle(Color(Theme.muted))
                .fixedSize(horizontal: false, vertical: true).lineBox(12)
        }
    }

    /// One row of the list: a radio mark, the AI's name, and who makes it (or "In use").
    private func choice(_ provider: AIProvider) -> some View {
        let selected = provider == chosen
        let inUse = store.hasAPIKey && provider == store.provider
        let note = inUse ? "In use" : provider == .grok ? "" : provider.company
        return Button { connection.choose(provider) } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(selected ? Color(Theme.accent) : .clear)
                    .overlay(Circle().strokeBorder(selected ? .clear : Color(Theme.muted), lineWidth: 1))
                    .overlay { if selected { Circle().fill(Color(Theme.onAction)).frame(width: 5, height: 5) } }
                    .frame(width: 15, height: 15)
                Text(provider.name).font(.system(size: 13, weight: .medium)).lineBox(13)
                Spacer(minLength: 0)
                Text(note).font(.system(size: 12))
                    .foregroundStyle(Color(selected ? Theme.ink : Theme.muted)).lineBox(12)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(selected ? Color(Theme.accentSoft) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.isEmpty ? provider.name : "\(provider.name), \(note)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Tidy can't tell a free Gemini key from a paid one, so this shows for every Gemini key.
    private var freeTierNotice: some View {
        (Text("Free keys aren’t private.").fontWeight(.semibold)
         + Text(" On Gemini’s free tier, Google may use your text to improve its products, and people may review it. Use a key from a paid project for private messages, or if you’re in the EEA, UK or Switzerland."))
            .font(.system(size: 12)).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(Theme.accentSoft)))
    }

    private var footnote: String {
        if sameAI { return "The new key replaces the one saved now." }
        if store.hasAPIKey {
            return "When this key connects, Tidy switches to \(chosen.name) and removes your \(store.provider.keyName) from this Mac. Your text then goes directly to \(chosen.company), billed to your account."
        }
        let subscription = chosen == .claude || chosen == .chatgpt ? " A \(chosen.name) subscription doesn’t include API use." : ""
        return "Your text goes directly to \(chosen.company), and API usage is billed to your account.\(subscription)"
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
        case .needsKey: return "Choose your AI and add its key to rewrite your own text."
        case .needsAccess: return "Allow Accessibility to clean up selected text. You can paste a draft into Tidy meanwhile."
        case .needsShortcut: return "Choose an available shortcut to open Tidy from another app."
        case .ready: return "Select text and use your shortcut to begin."
        }
    }
}
