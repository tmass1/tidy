import Foundation
import Combine
import Security
import TidyCore

@MainActor final class MobileStore: ObservableObject {
    static let group = "group.com.tommymassaro.tidy.mobile"
    let defaults: UserDefaults
    @Published var modes: [Mode] = []
    @Published var model = "claude-sonnet-5-5"
    @Published var voiceProfile = ""
    @Published var useVoice = true
    @Published var storageError: String?
    @Published var hasKey = false
    @Published var isPreview = false

    init() {
        defaults = UserDefaults(suiteName: Self.group)!
        reload()
    }
    func reload() {
        storageError = nil
        if let data = defaults.data(forKey: "modes") {
            do { modes = try Self.decodeModes(data) }
            catch { storageError = "Saved modes could not be read. Import a valid modes file in Settings."; modes = Mode.defaults }
        } else { modes = Mode.defaults }
        model = defaults.string(forKey: "model") ?? "claude-sonnet-5-5"
        voiceProfile = defaults.string(forKey: "voiceProfile") ?? ""
        useVoice = defaults.object(forKey: "useVoice") as? Bool ?? true
        do { hasKey = try MobileKeychain.read() != nil }
        catch { storageError = error.localizedDescription }
        #if DEBUG
        isPreview = defaults.bool(forKey: "previewTransport")
        #endif
    }
    func save() throws {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) != nil else {
            throw ClaudeError(message: "Shared storage is unavailable. Check App Group signing for both targets.")
        }
        defaults.set(try ModeFile.encode(modes), forKey: "modes")
        defaults.set(model, forKey: "model")
        defaults.set(voiceProfile, forKey: "voiceProfile")
        defaults.set(useVoice, forKey: "useVoice")
    }
    static func decodeModes(_ data: Data) throws -> [Mode] {
        try ModeFile.decode(data)
    }
    func exitPreview() {
        isPreview = false
        defaults.set(false, forKey: "previewTransport")
    }
    func stream(_ request: RewriteRequest) -> AsyncThrowingStream<String, Error> {
        #if DEBUG
        if isPreview { return SampleRewrite.stream(request) }
        #endif
        do {
            guard let key = try MobileKeychain.read() else {
                throw ClaudeError(message: "Add your Anthropic API key in the Tidy app’s Settings, then try again.")
            }
            return Claude.stream(apiKey: key, model: request.model, system: Prompts.system(voice: request.voice),
                                 user: Prompts.user(text: request.text, instruction: request.instruction, app: nil), requireComplete: true)
        } catch { return AsyncThrowingStream { $0.finish(throwing: error) } }
    }
}

enum MobileKeychain {
    private static func query() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TidyKeychainGroup") as? String,
              !group.contains("$("), !group.isEmpty else {
            throw ClaudeError(message: "Keychain sharing is not configured for this build.")
        }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.tommymassaro.tidy.mobile",
                kSecAttrAccount as String: "anthropic-api-key",
                kSecAttrAccessGroup as String: group]
    }
    static func read() throws -> String? {
        var q = try query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw failure(status)
        }
        return key.isEmpty ? nil : key
    }
    static func write(_ key: String) throws {
        let q = try query()
        let value = key.trimmed
        if value.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw failure(addStatus) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> ClaudeError {
        ClaudeError(message: "Couldn’t access the shared Keychain (\(status)). Unlock your device or check the signing configuration.")
    }
}

#if DEBUG
enum SampleRewrite {
    static let original = "hey! running like 15 mins late, the 101 is basically a parking lot. can we push dinner to 7:15? if you get there first put the table under Massaro and order the burrata for us. sorry i owe you a drink"
    static let final = "Hey! Running about 15 minutes behind, the 101 is a parking lot. Can we push dinner to 7:15? If you get there first, put the table under Massaro and order the burrata for us. Sorry, I owe you a drink."
    static let shorter = "Hey! I’m 15 minutes late—the 101 is a parking lot. Can we move dinner to 7:15? If you’re first, put the table under Massaro and order burrata for us. Sorry, I owe you a drink."
    static func stream(_ request: RewriteRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    let input = request.text.trimmed
                    guard [original, final, shorter].contains(input) else { throw ClaudeError(message: "This preview only rewrites the sample. Tap Exit sample to use your own text.") }
                    let output = request.instruction == Mode.defaults[2].instruction || input == shorter
                        ? shorter
                        : final
                    for word in output.split(separator: " ", omittingEmptySubsequences: false) {
                        try await Task.sleep(for: .milliseconds(45))
                        c.yield(String(word) + " ")
                    }
                    c.finish()
                } catch { c.finish(throwing: error) }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
