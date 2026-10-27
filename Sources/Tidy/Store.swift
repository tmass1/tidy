import AppKit
import Security
import ServiceManagement

struct Mode: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var instruction: String

    static var defaults: [Mode] {
        [
            Mode(name: "Clean up", instruction: "Fix spelling, grammar and punctuation, smooth awkward phrasing, and trim wordiness. Keep my voice, my tone and roughly the same length."),
            Mode(name: "Fix only", instruction: "Make the minimum edits needed: fix spelling, grammar, punctuation and obvious typos only. Do not rephrase, reorder or restyle anything else."),
            Mode(name: "Shorter", instruction: "Make it noticeably shorter and more direct while keeping every important point, request and detail. Cut filler, hedging and repetition."),
            Mode(name: "Warmer", instruction: "Make it warmer and friendlier while staying natural. Don't add gushing language, piles of exclamation marks, or emojis that weren't there."),
            Mode(name: "Polished", instruction: "Make it polished and professional, suitable for a client or an executive, without becoming stiff or longer."),
        ]
    }
}

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var app: String?
    var mode: String
    var original: String
    var suggestion: String
    var sent: String

    var edited: Bool { !suggestion.isEmpty && sent.trimmed != suggestion.trimmed }
}

enum Keychain {
    private static let service = "com.tommymassaro.tidy"
    private static let account = "anthropic-api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var modes: [Mode] { didSet { save(modes, to: "modes.json") } }
    @Published var history: [HistoryItem] { didSet { save(history, to: "history.json") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    @Published var shortcut: Shortcut {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut")
            registerHotKey()
        }
    }
    @Published var voiceProfile: String { didSet { UserDefaults.standard.set(voiceProfile, forKey: "voiceProfile") } }
    @Published var useVoice: Bool { didSet { UserDefaults.standard.set(useVoice, forKey: "useVoice") } }
    /// Update the voice profile on its own after a few edited sends (otherwise only on demand).
    @Published var learnFromEdits: Bool { didSet { UserDefaults.standard.set(learnFromEdits, forKey: "learnFromEdits") } }
    @Published var restoreClipboard: Bool { didSet { UserDefaults.standard.set(restoreClipboard, forKey: "restoreClipboard") } }
    @Published var voiceUpdatedAt: Date? { didSet { UserDefaults.standard.set(voiceUpdatedAt, forKey: "voiceUpdatedAt") } }
    /// Character limits per app, keyed by bundle identifier ("" when there's no source app).
    @Published var charLimits: [String: Int] { didSet { UserDefaults.standard.set(charLimits, forKey: "charLimits") } }
    @Published private(set) var hasAPIKey: Bool
    /// Set once the setup steps are finished or skipped; until then launch opens them.
    @Published var setupDone: Bool { didSet { UserDefaults.standard.set(setupDone, forKey: "setupDone") } }
    @Published var hotKeyRegistered = true
    @Published var settingsTab: SettingsTab = .general

    private let folder: URL
    private var cachedKey: String?
    private var isLearning = false

    private init() {
        let defaults = UserDefaults.standard
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tidy", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        folder = base

        modes = Store.load([Mode].self, from: base.appendingPathComponent("modes.json")) ?? Mode.defaults
        history = Store.load([HistoryItem].self, from: base.appendingPathComponent("history.json")) ?? []
        model = defaults.string(forKey: "model") ?? "claude-sonnet-5-5"
        shortcut = defaults.data(forKey: "shortcut")
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .defaultCleanup
        voiceProfile = defaults.string(forKey: "voiceProfile") ?? ""
        useVoice = defaults.object(forKey: "useVoice") as? Bool ?? true
        learnFromEdits = defaults.bool(forKey: "learnFromEdits")
        restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        voiceUpdatedAt = defaults.object(forKey: "voiceUpdatedAt") as? Date
        charLimits = defaults.dictionary(forKey: "charLimits") as? [String: Int] ?? [:]
        setupDone = defaults.bool(forKey: "setupDone")

        let key = Keychain.read()
        cachedKey = key
        hasAPIKey = !(key ?? "").isEmpty
    }

    // MARK: API key

    var apiKey: String? {
        guard let cachedKey, !cachedKey.isEmpty else { return nil }
        return cachedKey
    }

    func setAPIKey(_ value: String) {
        let key = value.trimmed
        Keychain.write(key)
        cachedKey = key
        hasAPIKey = !key.isEmpty
    }

    // MARK: Hotkey & login

    func registerHotKey() {
        hotKeyRegistered = HotKeyCenter.shared.register(shortcut)
        if !hotKeyRegistered { NSLog("Tidy: couldn't register \(shortcut.display), another app may own it") }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Tidy: launch at login change failed: \(error.localizedDescription)")
        }
    }

    // MARK: History & voice

    func addHistory(original: String, suggestion: String, sent: String, app: String?, mode: String) {
        history.insert(
            HistoryItem(date: Date(), app: app, mode: mode, original: original, suggestion: suggestion, sent: sent),
            at: 0
        )
        if history.count > 500 { history.removeLast(history.count - 500) }
        learnIfReady()
    }

    /// With "Learn my writing style" on, three new edited sends trigger a profile update.
    private func learnIfReady() {
        guard learnFromEdits, !isLearning, hasAPIKey, editsSinceVoiceUpdate.count >= 3 else { return }
        isLearning = true
        Task { @MainActor in
            do {
                try await learnVoice(samples: nil)
            } catch {
                NSLog("Tidy: automatic voice update failed: \(error.localizedDescription)")
            }
            isLearning = false
        }
    }

    var editsSinceVoiceUpdate: [HistoryItem] {
        let since = voiceUpdatedAt ?? .distantPast
        return history.filter { $0.edited && $0.date > since }
    }

    func learnVoice(samples: String?) async throws {
        guard let key = apiKey else { throw ClaudeError(message: "Add your API key in General first.") }
        let prompt = Prompts.voiceLearn(
            current: voiceProfile,
            edits: Array(editsSinceVoiceUpdate.prefix(25)),
            drafts: history.prefix(8).map(\.original),
            samples: samples
        )
        var out = ""
        for try await chunk in Claude.stream(apiKey: key, model: model, system: Prompts.voiceSystem, user: prompt, maxTokens: 1500) {
            out += chunk
        }
        let profile = out.trimmed
        guard !profile.isEmpty else { throw ClaudeError(message: "Claude returned an empty profile. Try again.") }
        voiceProfile = profile
        voiceUpdatedAt = Date()
    }

    // MARK: Files

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(value) {
            try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
    }
}
