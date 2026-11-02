import XCTest
@testable import TidyCore

@MainActor final class RewriteSessionTests: XCTestCase {
    let request = RewriteRequest(text: "hello", instruction: "Fix only", model: "test", voice: nil)
    func settle() async { for _ in 0..<20 { await Task.yield() } }
    func testStreamsAndCleansCompletedResult() async {
        let session = RewriteSession { _ in AsyncThrowingStream { c in
            c.yield("<message>Hi"); c.yield(" there</message>"); c.finish()
        }}
        session.run(request)
        await settle()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.result, "Hi there")
    }
    func testCancellationAndStaleResponseCannotOverwriteNextRun() async {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        let session = RewriteSession { _ in AsyncThrowingStream { streams.append($0) } }
        session.run(request)
        await settle()
        session.cancel()
        XCTAssertEqual(session.phase, .cancelled)
        session.run(request)
        await settle()
        guard streams.count == 2 else { return XCTFail("Expected two requests") }
        streams[0].yield("Stale"); streams[0].finish()
        streams[1].yield("Current"); streams[1].finish()
        await settle()
        XCTAssertEqual(session.result, "Current")
        XCTAssertEqual(session.phase, .ready)
    }
    func testEmptyResultFailsAndRetryReusesExactRequest() async {
        var requests: [String] = []
        let session = RewriteSession { request in
            requests.append(request.text)
            return AsyncThrowingStream { $0.finish() }
        }
        session.run(request); await settle()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertNotNil(session.error)
        session.original = "Changed draft"
        session.retry(); await settle()
        XCTAssertEqual(requests, ["hello", "hello"])
    }
    func testOversizedInputIsRejectedBeforeTransport() async {
        var called = false
        let session = RewriteSession { _ in called = true; return AsyncThrowingStream { $0.finish() } }
        session.run(RewriteRequest(text: String(repeating: "x", count: 20_001), instruction: "", model: "", voice: nil))
        await settle()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertFalse(called)
    }
}
