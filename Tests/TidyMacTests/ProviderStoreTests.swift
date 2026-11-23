import XCTest
@testable import Tidy
import TidyCore

/// Tidy uses one AI at a time: which one is saved, its key is the only key kept, and a switch
/// that fails changes nothing.
final class ProviderStoreTests: XCTestCase {
    /// A stand-in Keychain: one slot per AI.
    private final class Keys {
        var saved: [AIProvider: String] = [:]
        var failing = false
        var failingRemoval = false
        func write(_ value: String?, _ provider: AIProvider) throws {
            if failing { throw ClaudeError(message: "Storage unavailable") }
            if value == nil, failingRemoval { throw ClaudeError(message: "Couldn’t remove") }
            saved[provider] = value?.isEmpty == false ? value : nil
        }
    }

    @MainActor private func makeStore(_ keys: Keys, defaults: UserDefaults) -> Store {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidyProviderTests.\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return Store(defaults: defaults, folder: folder, readKey: { keys.saved[$0] }, writeKey: keys.write,
                     checkKey: { _, _ in .valid }, accessibilityAllowed: { true }, registersHotKey: false)
    }
    private func makeDefaults() -> UserDefaults {
        let id = "TidyProviderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: id)!
        addTeardownBlock { defaults.removePersistentDomain(forName: id) }
        return defaults
    }

    @MainActor func testAnInstallFromBeforeTheChoiceStaysOnClaude() {
        let keys = Keys(); keys.saved[.claude] = "existing-anthropic-key"
        let defaults = makeDefaults()
        defaults.set("claude-opus-5-5", forKey: "model")
        let store = makeStore(keys, defaults: defaults)
        XCTAssertEqual(store.provider, .claude)
        XCTAssertEqual(store.apiKey, "existing-anthropic-key")
        XCTAssertEqual(store.model, "claude-opus-5-5", "the model they picked is kept")
    }

    @MainActor func testSwitchingKeepsOnlyTheNewKeyAndIsRemembered() throws {
        let keys = Keys(); keys.saved[.claude] = "old-key"
        let defaults = makeDefaults()
        let store = makeStore(keys, defaults: defaults)
        try store.connect(.gemini, key: "  new-key  ")
        XCTAssertEqual(store.provider, .gemini)
        XCTAssertEqual(store.apiKey, "new-key")
        XCTAssertEqual(store.model, AIProvider.gemini.defaultModel)
        XCTAssertEqual(keys.saved, [.gemini: "new-key"], "the old AI's key is removed")

        let reopened = makeStore(keys, defaults: defaults)
        XCTAssertEqual(reopened.provider, .gemini)
        XCTAssertEqual(reopened.apiKey, "new-key")
        XCTAssertEqual(reopened.model, AIProvider.gemini.defaultModel)
    }

    @MainActor func testAFailedSwitchChangesNothing() {
        let keys = Keys(); keys.saved[.claude] = "old-key"
        let store = makeStore(keys, defaults: makeDefaults())
        store.model = "claude-haiku-5-5"
        keys.failing = true
        XCTAssertThrowsError(try store.connect(.chatgpt, key: "new-key"))
        XCTAssertEqual(store.provider, .claude)
        XCTAssertEqual(store.apiKey, "old-key")
        XCTAssertEqual(store.model, "claude-haiku-5-5")
        XCTAssertEqual(keys.saved, [.claude: "old-key"])
    }

    @MainActor func testReplacingTheSameAIsKeyKeepsItsModel() throws {
        let keys = Keys(); keys.saved[.claude] = "old-key"
        let store = makeStore(keys, defaults: makeDefaults())
        store.model = "claude-haiku-5-5"
        try store.setAPIKey("newer-key")
        XCTAssertEqual(store.provider, .claude)
        XCTAssertEqual(store.model, "claude-haiku-5-5")
        XCTAssertEqual(keys.saved, [.claude: "newer-key"])
    }

    @MainActor func testTheSwitchStillHappensIfTheOldKeyCantBeRemoved() throws {
        let keys = Keys(); keys.saved[.claude] = "old-key"
        let store = makeStore(keys, defaults: makeDefaults())
        keys.failingRemoval = true
        try store.connect(.grok, key: "new-key")
        XCTAssertEqual(store.provider, .grok)
        XCTAssertEqual(store.apiKey, "new-key")
    }

    @MainActor func testASavedModelFromAnotherAIFallsBackToTheDefault() {
        let keys = Keys(); keys.saved[.chatgpt] = "key"
        let defaults = makeDefaults()
        defaults.set("chatgpt", forKey: "provider")
        defaults.set("claude-opus-5-5", forKey: "model")
        XCTAssertEqual(makeStore(keys, defaults: defaults).model, AIProvider.chatgpt.defaultModel)
        defaults.set("not-a-provider", forKey: "provider")
        XCTAssertEqual(makeStore(keys, defaults: defaults).provider, .claude)
    }

    @MainActor func testConnectingThroughSettingsChecksAndSavesTheChosenAI() async {
        let keys = Keys(); keys.saved[.claude] = "old-key"
        var checked: [AIProvider] = []
        let defaults = makeDefaults()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidyProviderTests.\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = Store(defaults: defaults, folder: folder, readKey: { keys.saved[$0] }, writeKey: keys.write,
                          checkKey: { _, provider in checked.append(provider); return provider == .grok ? .rejected("Grok didn’t accept that key.") : .valid },
                          accessibilityAllowed: { true }, registersHotKey: false)
        XCTAssertEqual(store.connection.provider, .claude)

        store.connection.choose(.grok)
        store.connection.draft = "bad-key"
        await store.connection.connect()
        XCTAssertEqual(store.provider, .claude, "a rejected key leaves the AI in use alone")
        XCTAssertEqual(store.apiKey, "old-key")
        XCTAssertNotNil(store.connection.message)

        store.connection.choose(.chatgpt)
        XCTAssertNil(store.connection.message, "picking another AI clears the last error")
        store.connection.draft = "good-key"
        await store.connection.connect()
        XCTAssertEqual(checked, [.grok, .chatgpt])
        XCTAssertEqual(store.provider, .chatgpt)
        XCTAssertEqual(store.apiKey, "good-key")
        XCTAssertEqual(keys.saved, [.chatgpt: "good-key"])
        XCTAssertTrue(store.connection.saved)
    }

    @MainActor func testTheChoiceCantChangeWhileAKeyIsBeingChecked() async {
        var resume: CheckedContinuation<Claude.KeyCheck, Never>?
        var savedFor: AIProvider?
        let model = KeyConnectionModel(provider: .gemini, check: { _, _ in await withCheckedContinuation { resume = $0 } },
                                       save: { _, provider in savedFor = provider })
        model.draft = "candidate"
        let pending = Task { await model.connect() }
        while resume == nil { await Task.yield() }
        model.choose(.grok)
        XCTAssertEqual(model.provider, .gemini)
        resume?.resume(returning: .valid)
        await pending.value
        XCTAssertEqual(savedFor, .gemini)
    }

    @MainActor func testACleanupGoesToTheAIInUse() async {
        let keys = Keys(); keys.saved[.chatgpt] = "openai-key"
        let defaults = makeDefaults()
        defaults.set("chatgpt", forKey: "provider")
        let store = makeStore(keys, defaults: defaults)
        var sent: (AIProvider, String, String)?
        let model = PanelModel(store: store, transport: { provider, key, model, _, _ in
            sent = (provider, key, model)
            return AsyncThrowingStream { $0.yield("A cleaned sample."); $0.finish() }
        })
        model.tryOnSample()
        while model.isStreaming { await Task.yield() }
        XCTAssertEqual(sent?.0, .chatgpt)
        XCTAssertEqual(sent?.1, "openai-key")
        XCTAssertEqual(sent?.2, AIProvider.chatgpt.defaultModel)
    }

    @MainActor func testTheModelMenuNamesTheModelOfTheAIInUse() {
        XCTAssertEqual(ModelMenu.label(for: "gpt-6-luna", in: .chatgpt), "GPT-6 Luna")
        XCTAssertEqual(ModelMenu.label(for: "claude-sonnet-5-5", in: .claude), "Sonnet 5.5")
        XCTAssertEqual(ModelMenu.label(for: "grok-4.7", in: .grok), "Grok 4.7")
    }
}
