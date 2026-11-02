import TidyCore
import AppKit
import Security
import ServiceManagement

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

    static func write(_ value: String?) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(base.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> ClaudeError {
        ClaudeError(message: "Couldn’t save to your Keychain (\(status)). Unlock your Keychain and try again.")
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var modes: [Mode] { didSet { save(modes, to: "modes.json") } }
    @Published var history: [HistoryItem] { didSet { save(history, to: "history.json") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut")
            registerHotKey()
        }
    }
    @Published var voiceProfile: String { didSet { defaults.set(voiceProfile, forKey: "voiceProfile") } }
    @Published var useVoice: Bool { didSet { defaults.set(useVoice, forKey: "useVoice") } }
    /// Update the voice profile on its own after a few edited sends (otherwise only on demand).
    @Published var learnFromEdits: Bool { didSet { defaults.set(learnFromEdits, forKey: "learnFromEdits") } }
    @Published var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: "restoreClipboard") } }
    @Published var voiceUpdatedAt: Date? { didSet { defaults.set(voiceUpdatedAt, forKey: "voiceUpdatedAt") } }
    /// Character limits per app, keyed by bundle identifier ("" when there's no source app).
    @Published var charLimits: [String: Int] { didSet { defaults.set(charLimits, forKey: "charLimits") } }
    @Published private(set) var hasAPIKey: Bool
    /// Set once the setup steps are finished or skipped; until then launch opens them.
    @Published var setupDone: Bool { didSet { defaults.set(setupDone, forKey: "setupDone") } }
    @Published var hotKeyRegistered = true
    @Published var settingsTab: SettingsTab = .general
    @Published var moreOptionsExpanded = false
    @Published var isRecordingShortcut = false

    private let folder: URL
    private var cachedKey: String?
    private var isLearning = false

    private let defaults: UserDefaults
    private let writeKey: (String?) throws -> Void
    private let registersHotKey: Bool
    let checkKey: (String) async -> Claude.KeyCheck
    let accessibilityAllowed: () -> Bool
    let isDesignPreview: Bool
    lazy var connection = KeyConnectionModel(check: checkKey, save: { [weak self] value in
        guard let self else { throw ClaudeError(message: "Tidy is no longer available.") }
        try self.setAPIKey(value)
    })

    init(defaults: UserDefaults = .standard, folder: URL? = nil,
         readKey: () -> String? = Keychain.read,
         writeKey: @escaping (String?) throws -> Void = Keychain.write,
         checkKey: @escaping (String) async -> Claude.KeyCheck = Claude.checkKey,
         accessibilityAllowed: @escaping () -> Bool = { Selection.isTrusted(prompt: false) },
         registersHotKey: Bool = true, isDesignPreview: Bool = false) {
        self.defaults = defaults; self.writeKey = writeKey; self.checkKey = checkKey
        self.accessibilityAllowed = accessibilityAllowed
        self.registersHotKey = registersHotKey; self.isDesignPreview = isDesignPreview
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tidy", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.folder = base

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

        let key = readKey()
        cachedKey = key
        hasAPIKey = !(key ?? "").isEmpty
    }

    // MARK: API key

    var apiKey: String? {
        guard let cachedKey, !cachedKey.isEmpty else { return nil }
        return cachedKey
    }

    func setAPIKey(_ value: String) throws {
        let key = value.trimmed
        try writeKey(key)
        cachedKey = key
        hasAPIKey = !key.isEmpty
    }

    // MARK: Hotkey & login

    func registerHotKey() {
        guard registersHotKey else { return }
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
        guard !isDesignPreview else { throw ClaudeError(message: "Voice learning is unavailable in the design preview.") }
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
