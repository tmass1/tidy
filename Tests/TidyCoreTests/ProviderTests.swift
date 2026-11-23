import XCTest
@testable import TidyCore

final class ProviderTests: XCTestCase {
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
    private func request(_ provider: AIProvider, _ model: String) throws -> URLRequest {
        try AI.request(provider: provider, apiKey: "test-key", model: model, system: "Be brief.", user: "hello", maxTokens: 4096)
    }
    private func text(_ lines: [String], _ provider: AIProvider = .chatgpt) throws -> (String, Bool) {
        var decoder = TextStreamDecoder(provider: provider)
        var out = ""
        for line in lines { out += try decoder.consume(line) ?? "" }
        return (out, decoder.finished)
    }

    func testEveryProviderHasModelsAndAValidDefault() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.models.isEmpty)
            XCTAssertTrue(provider.models.contains { $0.id == provider.defaultModel }, provider.name)
            XCTAssertEqual(provider.model(orDefault: "not-a-model"), provider.defaultModel)
            XCTAssertEqual(provider.model(orDefault: nil), provider.defaultModel)
            XCTAssertEqual(provider.model(orDefault: provider.models[0].id), provider.models[0].id)
        }
        XCTAssertEqual(AIProvider.claude.models.map(\.id), Claude.models.map(\.id))
        let all = AIProvider.allCases.flatMap { $0.models.map(\.id) }
        XCTAssertEqual(Set(all).count, all.count, "a model ID belongs to one provider")
    }

    func testKeyNamesReadNaturally() {
        XCTAssertEqual(AIProvider.chatgpt.aKey, "an OpenAI API key")
        XCTAssertEqual(AIProvider.claude.aKey, "an Anthropic API key")
        XCTAssertEqual(AIProvider.gemini.aKey, "a Gemini API key")
        XCTAssertEqual(AIProvider.grok.aKey, "a Grok API key")
    }

    func testChatGPTRequest() throws {
        let fast = try request(.chatgpt, "gpt-6-luna")
        XCTAssertEqual(fast.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(fast.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let json = try body(fast)
        XCTAssertEqual(json["instructions"] as? String, "Be brief.")
        XCTAssertEqual(json["input"] as? String, "hello")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["store"] as? Bool, false, "ask OpenAI not to keep the response")
        XCTAssertEqual((json["reasoning"] as? [String: String])?["effort"], "none")
        XCTAssertEqual(json["max_output_tokens"] as? Int, 4096)

        let careful = try body(request(.chatgpt, "gpt-6.2-astra"))
        XCTAssertEqual((careful["reasoning"] as? [String: String])?["effort"], "low", "Astra rejects none")
        XCTAssertEqual(careful["max_output_tokens"] as? Int, 8192, "room for thinking, which counts toward the limit")
    }

    func testGrokRequest() throws {
        let fast = try request(.grok, "grok-4.20-0309-non-reasoning")
        XCTAssertEqual(fast.url?.absoluteString, "https://api.x.ai/v1/responses")
        let json = try body(fast)
        XCTAssertEqual(json["store"] as? Bool, false, "ask Grok not to keep the response")
        XCTAssertNil(json["reasoning"], "the non-reasoning model gets no thinking setting")
        XCTAssertEqual(json["max_output_tokens"] as? Int, 4096)
        XCTAssertEqual((try body(request(.grok, "grok-4.7"))["reasoning"] as? [String: String])?["effort"], "low")
    }

    func testGeminiRequest() throws {
        let balanced = try request(.gemini, "gemini-3.8-flash")
        XCTAssertEqual(balanced.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        XCTAssertEqual(balanced.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let json = try body(balanced)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.map { $0["content"] }, ["Be brief.", "hello"])
        XCTAssertEqual(json["reasoning_effort"] as? String, "low", "minimal is an error on 3.8 Flash")
        XCTAssertNil(try body(request(.gemini, "gemini-3.5-flash-lite"))["reasoning_effort"])
    }

    func testClaudeKeepsItsOwnClient() {
        XCTAssertThrowsError(try request(.claude, "claude-sonnet-5-5"))
    }

    func testDecodesResponsesEvents() throws {
        let (out, finished) = try text([
            "event: response.output_text.delta",
            #"data: {"type":"response.created","response":{}}"#,
            #"data: {"type":"response.output_text.delta","delta":"Hey! "}"#,
            #"data: {"type":"response.output_text.delta","delta":"Running late."}"#,
            #"data: {"type":"response.completed","response":{}}"#,
        ])
        XCTAssertEqual(out, "Hey! Running late.")
        XCTAssertTrue(finished)
    }

    func testDecodesChatCompletionChunks() throws {
        let (out, finished) = try text([
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hey! "}}]}"#,
            #"data: {"choices":[{"delta":{"content":"Running late."},"finish_reason":"stop"}]}"#,
            "data: [DONE]",
        ], .gemini)
        XCTAssertEqual(out, "Hey! Running late.")
        XCTAssertTrue(finished)
    }

    func testStreamErrorsStopTheRewrite() {
        let cases: [(String, String)] = [
            (#"data: {"type":"error","message":"Server overloaded"}"#, "Server overloaded"),
            (#"data: {"type":"response.failed","response":{"error":{"message":"Model unavailable"}}}"#, "Model unavailable"),
            (#"data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#, "length limit"),
            (#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#, "length limit"),
            (#"data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#, "could not rewrite"),
            (#"data: {"error":{"message":"Bad request"}}"#, "Bad request"),
        ]
        for (line, expected) in cases {
            XCTAssertThrowsError(try text([line])) { error in
                XCTAssertTrue(error.localizedDescription.contains(expected), "\(line) → \(error.localizedDescription)")
            }
        }
    }

    func testUnreadableLinesAreSkipped() throws {
        let (out, finished) = try text([": keep-alive", "data: not json", "", #"data: {"type":"response.output_text.delta","delta":"ok"}"#])
        XCTAssertEqual(out, "ok")
        XCTAssertFalse(finished)
    }

    func testKeyCheckReadsEachCompanysAnswer() {
        XCTAssertEqual(AI.keyCheck(provider: .chatgpt, status: 200, data: Data()), .valid)
        XCTAssertEqual(AI.keyCheck(provider: .chatgpt, status: 401, data: Data()),
                       .rejected("OpenAI didn’t accept that key. Check that you copied all of it."))
        XCTAssertEqual(AI.keyCheck(provider: .grok, status: 401, data: Data(#"{"code":"x","error":"Incorrect API key"}"#.utf8)),
                       .rejected("Grok didn’t accept that key. Check that you copied all of it."))
        let google = Data(#"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key."}}]"#.utf8)
        XCTAssertEqual(AI.keyCheck(provider: .gemini, status: 400, data: google),
                       .rejected("Google didn’t accept that key. Check that you copied all of it."))
        if case .unreachable = AI.keyCheck(provider: .gemini, status: 400, data: Data(#"{"error":{"message":"Bad model"}}"#.utf8)) {} else {
            XCTFail("a 400 that isn't about the key is not a rejected key")
        }
        if case .unreachable = AI.keyCheck(provider: .chatgpt, status: 503, data: Data()) {} else { XCTFail("503 is not a rejected key") }
    }

    func testErrorMessages() {
        XCTAssertEqual(AI.apiMessage(Data(#"{"error":{"message":"nested"}}"#.utf8)), "nested")
        XCTAssertEqual(AI.apiMessage(Data(#"{"error":"flat"}"#.utf8)), "flat")
        XCTAssertEqual(AI.apiMessage(Data(#"[{"error":{"message":"listed"}}]"#.utf8)), "listed")
        XCTAssertNil(AI.apiMessage(Data("not json".utf8)))
        XCTAssertEqual(AI.errorMessage(provider: .chatgpt, status: 401, data: Data()), "Your API key was rejected. Check it in Settings (⌘,).")
        XCTAssertEqual(AI.errorMessage(provider: .gemini, status: 503, data: Data()), "Gemini is having trouble right now. Press ⌘R to try again.")
        let quota = Data(#"{"error":{"message":"You exceeded your current quota.","code":"insufficient_quota"}}"#.utf8)
        XCTAssertTrue(AI.errorMessage(provider: .chatgpt, status: 429, data: quota).contains("OpenAI account is out of API credit"))
        XCTAssertEqual(AI.errorMessage(provider: .grok, status: 429, data: Data()), "Rate limited. Wait a moment and press ⌘R.")
        XCTAssertEqual(AI.errorMessage(provider: .grok, status: 418, data: Data()), "Request failed (HTTP 418).")
    }
}
