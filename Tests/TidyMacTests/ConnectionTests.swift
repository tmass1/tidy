import XCTest
@testable import Tidy
import TidyCore

final class ConnectionTests: XCTestCase {
    @MainActor func testValidConnectionSavesTrimmedKeyAndClearsDraft() async {
        var written: String?
        let model = KeyConnectionModel(check: { _, _ in .valid }, save: { key, _ in written = key })
        model.draft = "  test-key  "
        await model.connect()
        XCTAssertEqual(written, "test-key")
        XCTAssertTrue(model.saved)
        XCTAssertEqual(model.draft, "")
        XCTAssertFalse(model.checking)
    }
    @MainActor func testRejectedAndOfflineNeverSave() async {
        for outcome in [Claude.KeyCheck.rejected("Invalid key"), .unreachable("Offline")] {
            var writes = 0
            let model = KeyConnectionModel(check: { _, _ in outcome }, save: { _, _ in writes += 1 })
            model.draft = "candidate"
            await model.connect()
            XCTAssertEqual(writes, 0)
            XCTAssertFalse(model.saved)
            XCTAssertNotNil(model.message)
            XCTAssertEqual(model.draft, "candidate")
        }
    }
    @MainActor func testPersistenceFailureDoesNotShowSuccess() async {
        let model = KeyConnectionModel(check: { _, _ in .valid }, save: { _, _ in throw ClaudeError(message: "Keychain locked") })
        model.draft = "candidate"
        await model.connect()
        XCTAssertFalse(model.saved)
        XCTAssertEqual(model.message, "Keychain locked")
        XCTAssertEqual(model.draft, "candidate")
    }
    @MainActor func testCancelIgnoresLateValidation() async {
        var resume: CheckedContinuation<Claude.KeyCheck, Never>?
        var writes = 0
        let model = KeyConnectionModel(check: { _, _ in await withCheckedContinuation { resume = $0 } }, save: { _, _ in writes += 1 })
        model.draft = "candidate"
        let pending = Task { await model.connect() }
        while resume == nil { await Task.yield() }
        model.cancel()
        resume?.resume(returning: .valid)
        await pending.value
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(model.saved)
        XCTAssertFalse(model.checking)
        XCTAssertEqual(model.draft, "")
    }
}
