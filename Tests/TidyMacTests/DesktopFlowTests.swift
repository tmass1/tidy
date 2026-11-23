import XCTest
import AppKit
@testable import Tidy
import TidyCore

final class DesktopFlowTests: XCTestCase {
    @MainActor private func store(write: @escaping (String?) throws -> Void = { _ in }) -> Store {
        let id = "TidyTests.\(UUID())"
        let defaults = UserDefaults(suiteName: id)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        addTeardownBlock { defaults.removePersistentDomain(forName: id); try? FileManager.default.removeItem(at: folder) }
        return Store(defaults: defaults, folder: folder, readKey: { "existing-test-key" }, writeKey: write,
                     accessibilityAllowed: { true }, registersHotKey: false)
    }
    @MainActor func testFailedReplacementPreservesCachedCredential() throws {
        let store = store { _ in throw ClaudeError(message: "Storage unavailable") }
        XCTAssertThrowsError(try store.setAPIKey("replacement"))
        XCTAssertTrue(store.hasAPIKey)
        XCTAssertEqual(store.apiKey, "existing-test-key")
    }
    @MainActor func testPreviewRejectsVoiceLearningBeforeCredentialOrNetworkAccess() async {
        let id = "TidyVoicePreviewTest.\(UUID())"
        let defaults = UserDefaults(suiteName: id)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        defer { defaults.removePersistentDomain(forName: id); try? FileManager.default.removeItem(at: folder) }
        let store = Store(defaults: defaults, folder: folder, readKey: { nil }, writeKey: { _ in },
                          registersHotKey: false, isDesignPreview: true)
        do { try await store.learnVoice(samples: "Example text"); XCTFail("Preview must block voice learning") }
        catch { XCTAssertEqual(error.localizedDescription, "Voice learning is unavailable in the design preview.") }
    }
    @MainActor func testClosingPanelCancelsPendingKeySave() async {
        let id = "TidyClosingTest.\(UUID())"
        let defaults = UserDefaults(suiteName: id)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        defer { defaults.removePersistentDomain(forName: id); try? FileManager.default.removeItem(at: folder) }
        var resume: CheckedContinuation<Claude.KeyCheck, Never>?
        var writes = 0
        let store = Store(defaults: defaults, folder: folder, readKey: { nil }, writeKey: { _ in writes += 1 },
                          checkKey: { _ in await withCheckedContinuation { resume = $0 } }, registersHotKey: false)
        let controller = PanelController(store: store)
        store.connection.draft = "test-candidate"
        let pending = Task { await store.connection.connect() }
        while resume == nil { await Task.yield() }
        controller.close()
        resume?.resume(returning: .valid)
        await pending.value
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(store.hasAPIKey)
    }
    @MainActor func testReadinessRequiresAllThreeCapabilities() {
        for key in [false, true] {
            for access in [false, true] {
                for shortcut in [false, true] {
                    let state = SetupReadiness(hasKey: key, hasAccess: access, hasShortcut: shortcut)
                    XCTAssertEqual(state == .ready, key && access && shortcut)
                }
            }
        }
    }
    @MainActor func testClosingPanelEndsShortcutRecording() {
        let store = store()
        let controller = PanelController(store: store)
        store.isRecordingShortcut = true
        controller.close()
        XCTAssertFalse(store.isRecordingShortcut)
    }
    @MainActor func testSettingsNavigationPreservesDraftResultAndSource() {
        let store = store()
        let model = PanelModel(store: store)
        let source = NSRunningApplication.current
        model.reset(original: "My draft", source: source, hadSelection: true)
        model.result = "My edited draft"
        model.openSettings(.general)
        model.openSettings(.voice)
        model.page = .editor
        XCTAssertEqual(model.original, "My draft")
        XCTAssertEqual(model.result, "My edited draft")
        XCTAssertEqual(model.sourceApp, source)
        XCTAssertTrue(model.hadSelection)
        XCTAssertTrue(model.replaceTitle.hasPrefix("Replace"))
    }
    @MainActor func testSampleKeepsLabelAfterCompletionAndExitClearsIt() async {
        let model = PanelModel(store: store(), transport: { _, _, _, _ in
            AsyncThrowingStream { $0.yield("A cleaned sample."); $0.finish() }
        })
        model.tryOnSample()
        while model.isStreaming { await Task.yield() }
        XCTAssertTrue(model.isTrial)
        XCTAssertEqual(model.result, "A cleaned sample.")
        model.exitSample()
        XCTAssertFalse(model.isTrial)
        XCTAssertEqual(model.original, "")
        XCTAssertEqual(model.result, "")
        XCTAssertFalse(model.canCommit)
    }
    @MainActor func testExitingSampleCancelsLateOutput() async {
        var stream: AsyncThrowingStream<String, Error>.Continuation?
        let model = PanelModel(store: store(), transport: { _, _, _, _ in
            AsyncThrowingStream { stream = $0 }
        })
        model.tryOnSample()
        await Task.yield()
        model.exitSample()
        stream?.yield("Late sample text")
        stream?.finish()
        await Task.yield()
        XCTAssertEqual(model.result, "")
        XCTAssertFalse(model.isTrial)
        XCTAssertFalse(model.isStreaming)
    }
}
