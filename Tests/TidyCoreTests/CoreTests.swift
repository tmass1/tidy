import XCTest
@testable import TidyCore

final class CoreTests: XCTestCase {
    func testExistingModesAndPromptContract() {
        XCTAssertEqual(Mode.defaults.map(\.name), ["Clean up", "Fix only", "Shorter", "Warmer", "Polished"])
        let prompt = Prompts.user(text: "Meet at 7:15", instruction: Mode.defaults[1].instruction, app: nil)
        XCTAssertTrue(prompt.contains("Do not rephrase, reorder or restyle anything else."))
        XCTAssertTrue(prompt.hasSuffix("<message>\nMeet at 7:15\n</message>"))
        XCTAssertFalse(prompt.contains("Being written in:"))
        XCTAssertTrue(Prompts.system(voice: "- Keep it casual").hasSuffix("- Keep it casual"))
    }
    func testStreamingWrapperCleanup() {
        XCTAssertEqual(Prompts.clean("<mess", streaming: true), "")
        XCTAssertEqual(Prompts.clean("<message>\nHello</message>", streaming: false), "Hello")
        XCTAssertEqual(Prompts.clean("```text\nHello\n```", streaming: false), "Hello")
    }
    func testDiffReconstructsBothTextsIncludingWhitespace() throws {
        let a = "Hi  there.\nMeet Friday?", b = "Hello there.\nMeet Friday at 3?"
        let chunks = try XCTUnwrap(WordDiff.diff(a, b))
        XCTAssertEqual(chunks.filter { $0.op != .ins }.map(\.text).joined(), a)
        XCTAssertEqual(chunks.filter { $0.op != .del }.map(\.text).joined(), b)
        XCTAssertNil(WordDiff.diff(String(repeating: "a ", count: 1000), String(repeating: "b ", count: 1000)))
    }
    func testModeJSONRoundTripPreservesIDsAndInstructions() throws {
        let modes = Mode.defaults
        XCTAssertEqual(try JSONDecoder().decode([Mode].self, from: JSONEncoder().encode(modes)), modes)
    }
    func testModeFileRejectsTooManyModesBeforeSaving() {
        let modes = (0..<101).map { Mode(name: "Mode \($0)", instruction: "Fix spelling") }
        XCTAssertThrowsError(try ModeFile.encode(modes))
    }
    func testModeFileRejectsInvalidImportsAndOversizedCollection() throws {
        let duplicate = Mode(name: "A", instruction: "B")
        XCTAssertThrowsError(try ModeFile.decode(JSONEncoder().encode([duplicate, duplicate])))
        let big = (0..<100).map { Mode(name: "Mode \($0)", instruction: String(repeating: "x", count: 10_000)) }
        XCTAssertThrowsError(try ModeFile.encode(big))
    }
    func testTruncatedStreamCannotBeSuccessful() {
        var decoder = MessageStreamDecoder()
        XCTAssertThrowsError(try decoder.finish())
    }
    func testSSETextAndCompletion() throws {
        var decoder = MessageStreamDecoder()
        XCTAssertEqual(try decoder.consume("data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello 🌱\"}}"), "Hello 🌱")
        _ = try decoder.consume("data: {\"type\":\"message_stop\"}")
        XCTAssertNoThrow(try decoder.finish())
    }
    func testTokenLimitIsNotACompleteRewrite() {
        var decoder = MessageStreamDecoder()
        XCTAssertThrowsError(try decoder.consume("data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"max_tokens\"}}"))
    }
}
