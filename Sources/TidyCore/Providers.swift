import Foundation

/// The AIs Tidy can write with. One is in use at a time, with the user's own API key.
public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case claude, chatgpt, gemini, grok

    public var id: String { rawValue }

    /// What people pick: "ChatGPT".
    public var name: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .gemini: "Gemini"
        case .grok: "Grok"
        }
    }

    /// Who the text goes to and who bills for it: "OpenAI". Grok's own docs mix two company names,
    /// so it goes by the product's.
    public var company: String {
        switch self {
        case .claude: "Anthropic"
        case .chatgpt: "OpenAI"
        case .gemini: "Google"
        case .grok: "Grok"
        }
    }

    /// What the key is called where people get it: "OpenAI API key".
    public var keyName: String {
        switch self {
        case .claude: "Anthropic API key"
        case .chatgpt: "OpenAI API key"
        case .gemini: "Gemini API key"
        case .grok: "Grok API key"
        }
    }

    /// "an OpenAI API key", "a Gemini API key".
    public var aKey: String {
        switch self {
        case .claude, .chatgpt: "an \(keyName)"
        case .gemini, .grok: "a \(keyName)"
        }
    }

    public var keysURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .chatgpt: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .grok: URL(string: "https://console.x.ai/team/default/api-keys")!
        }
    }

    /// Model IDs live only here and in `Claude.models`. Check each company's current list before
    /// changing them: docs.claude.com, developers.openai.com/api/docs/models,
    /// ai.google.dev/gemini-api/docs/models, docs.x.ai/developers/models.
    public var models: [ModelOption] {
        switch self {
        case .claude:
            Claude.models
        case .chatgpt:
            [ModelOption(id: "gpt-6-luna", name: "GPT-6 Luna · fastest", short: "Luna"),
             ModelOption(id: "gpt-6.2-sol", name: "GPT-6.2 Sol · balanced", short: "Sol"),
             ModelOption(id: "gpt-6.2-astra", name: "GPT-6.2 Astra · most careful", short: "Astra")]
        case .gemini:
            [ModelOption(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite · fastest", short: "Flash-Lite"),
             ModelOption(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash · balanced", short: "Flash"),
             ModelOption(id: "gemini-4-carbon", name: "Gemini 4 Carbon · most careful", short: "Carbon")]
        case .grok:
            [ModelOption(id: "grok-4.20-0309-non-reasoning", name: "Grok 4.20 · fastest", short: "Grok 4.20"),
             ModelOption(id: "grok-4.7", name: "Grok 4.7 · most careful", short: "Grok 4.7")]
        }
    }

    /// The balanced model where there is one, like Claude's Sonnet; otherwise the fastest.
    public var defaultModel: String {
        switch self {
        case .claude: "claude-sonnet-5-5"
        case .chatgpt: "gpt-6.2-sol"
        case .gemini: "gemini-3.8-flash"
        case .grok: "grok-4.20-0309-non-reasoning"
        }
    }

    /// The model to use: the saved one if this AI has it, else its default.
    public func model(orDefault saved: String?) -> String {
        guard let saved, models.contains(where: { $0.id == saved }) else { return defaultModel }
        return saved
    }

    /// The lowest thinking setting each model accepts, so a rewrite stays quick. nil sends none:
    /// the model has no setting, or its docs don't say which values it takes.
    func effort(for model: String) -> String? {
        switch model {
        case "gpt-6-luna": "none"
        case "gpt-6.2-sol", "gpt-6.2-astra": "low"
        case "gemini-3.8-flash", "gemini-4-carbon": "low"
        case "grok-4.7": "low"
        default: nil
        }
    }
}

/// One streaming client for every AI. Claude goes through `Claude`, as before.
public enum AI {
    public static func stream(
        provider: AIProvider, apiKey: String, model: String, system: String, user: String, maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        if provider == .claude {
            return Claude.stream(apiKey: apiKey, model: model, system: system, user: user, maxTokens: maxTokens)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try request(
                        provider: provider, apiKey: apiKey, model: model, system: system, user: user, maxTokens: maxTokens)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw ClaudeError(message: errorMessage(provider: provider, status: status, data: data))
                    }
                    var decoder = TextStreamDecoder(provider: provider)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if let text = try decoder.consume(line) { continuation.yield(text) }
                        if decoder.finished { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The request for ChatGPT, Gemini or Grok. `store: false` asks OpenAI and Grok not to keep
    /// the response; both keep it for 30 days otherwise.
    static func request(
        provider: AIProvider, apiKey: String, model: String, system: String, user: String, maxTokens: Int
    ) throws -> URLRequest {
        let effort = provider.effort(for: model)
        let url: String
        var body: [String: Any] = ["model": model, "stream": true]
        switch provider {
        case .claude:
            throw ClaudeError(message: "Claude uses its own client.")
        case .chatgpt, .grok:
            url = provider == .chatgpt ? "https://api.openai.com/v1/responses" : "https://api.x.ai/v1/responses"
            body["instructions"] = system
            body["input"] = user
            body["store"] = false
            // OpenAI counts thinking toward the limit, so a thinking model gets room for it.
            // Grok counts only what it writes.
            let thinks = provider == .chatgpt && effort != nil && effort != "none"
            body["max_output_tokens"] = thinks ? maxTokens + 4096 : maxTokens
            if let effort { body["reasoning"] = ["effort": effort] }
        case .gemini:
            // Gemini's OpenAI-compatible endpoint. No output limit is sent: its docs don't name the field.
            url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            body["messages"] = [["role": "system", "content": system], ["role": "user", "content": user]]
            if let effort { body["reasoning_effort"] = effort }
        }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Checks a key by listing models, which costs nothing.
    public static func checkKey(_ key: String, provider: AIProvider) async -> Claude.KeyCheck {
        if provider == .claude { return await Claude.checkKey(key) }
        var request = URLRequest(url: modelsURL(provider))
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return keyCheck(provider: provider, status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    static func modelsURL(_ provider: AIProvider) -> URL {
        switch provider {
        case .claude: URL(string: "https://api.anthropic.com/v1/models?limit=1")!
        case .chatgpt: URL(string: "https://api.openai.com/v1/models")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/models")!
        case .grok: URL(string: "https://api.x.ai/v1/models")!
        }
    }

    static func keyCheck(provider: AIProvider, status: Int, data: Data) -> Claude.KeyCheck {
        let rejected = Claude.KeyCheck.rejected("\(provider.company) didn’t accept that key. Check that you copied all of it.")
        switch status {
        case 200: return .valid
        case 401: return rejected
        case 403: return .rejected("That key isn’t allowed to use the API.")
        // Google answers a bad key with 400, not 401.
        case 400 where apiMessage(data)?.localizedCaseInsensitiveContains("api key") == true: return rejected
        default: return .unreachable(errorMessage(provider: provider, status: status, data: data))
        }
    }

    static func errorMessage(provider: AIProvider, status: Int, data: Data) -> String {
        let message = apiMessage(data)
        if message?.localizedCaseInsensitiveContains("quota") == true || message?.localizedCaseInsensitiveContains("credit") == true {
            return "Your \(provider.company) account is out of API credit, or over its limit. Check your account, then press ⌘R."
        }
        switch status {
        case 400 where message?.localizedCaseInsensitiveContains("api key") == true, 401:
            return "Your API key was rejected. Check it in Settings (⌘,)."
        case 403: return "This API key doesn't have access to that model."
        case 404: return "Model not found. Pick a different model in Settings."
        case 429: return "Rate limited. Wait a moment and press ⌘R."
        case 500, 502, 503, 529: return "\(provider.name) is having trouble right now. Press ⌘R to try again."
        default: return message ?? "Request failed (HTTP \(status))."
        }
    }

    /// The message in an error body. OpenAI nests it (`error.message`), Grok sends `error` as text,
    /// and Google can wrap the whole body in a list.
    static func apiMessage(_ data: Data) -> String? {
        var json = try? JSONSerialization.jsonObject(with: data)
        if let list = json as? [Any] { json = list.first }
        guard let body = json as? [String: Any] else { return nil }
        if let error = body["error"] as? [String: Any] { return error["message"] as? String }
        return (body["error"] as? String) ?? (body["message"] as? String)
    }
}

/// Reads the text out of a streamed reply from ChatGPT, Gemini or Grok. It accepts both shapes
/// these APIs send: Responses events (`response.output_text.delta`) and Chat Completions chunks
/// (`choices[0].delta.content`), ending with `response.completed` or `data: [DONE]`.
struct TextStreamDecoder {
    let provider: AIProvider
    private(set) var finished = false

    mutating func consume(_ line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { finished = true; return nil }
        guard let data = payload.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        if let type = event["type"] as? String {
            switch type {
            case "response.output_text.delta":
                return event["delta"] as? String
            case "response.completed":
                finished = true
            case "response.incomplete":
                let details = (event["response"] as? [String: Any])?["incomplete_details"] as? [String: Any]
                throw ClaudeError(message: details?["reason"] as? String == "content_filter" ? refused : tooLong)
            case "response.failed":
                let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
                throw ClaudeError(message: (error?["message"] as? String) ?? "The API returned an error.")
            case "error":
                let nested = (event["error"] as? [String: Any])?["message"] as? String
                throw ClaudeError(message: (event["message"] as? String) ?? nested ?? "The API returned an error.")
            default:
                break
            }
            return nil
        }
        if let choice = (event["choices"] as? [[String: Any]])?.first {
            let text = (choice["delta"] as? [String: Any])?["content"] as? String
            switch choice["finish_reason"] as? String {
            case "length": throw ClaudeError(message: tooLong)
            case "content_filter": throw ClaudeError(message: refused)
            default: break
            }
            return text
        }
        if event["error"] != nil {
            throw ClaudeError(message: AI.apiMessage(data) ?? "The API returned an error.")
        }
        return nil
    }

    private var tooLong: String { "The response reached its length limit. Try a shorter message." }
    private var refused: String { "\(provider.name) could not rewrite this message. Try changing the text." }
}
