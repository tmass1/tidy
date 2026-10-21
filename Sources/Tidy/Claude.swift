import Foundation

struct ModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
}

struct ClaudeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Minimal streaming client for the Anthropic Messages API.
enum Claude {
    static let models: [ModelOption] = [
        ModelOption(id: "claude-haiku-5-5", name: "Haiku 5.5 · fastest", short: "Haiku"),
        ModelOption(id: "claude-sonnet-5-5", name: "Sonnet 5.5 · balanced", short: "Sonnet"),
        ModelOption(id: "claude-opus-5-5", name: "Opus 5.5 · most careful", short: "Opus"),
    ]

    static func shortName(_ id: String) -> String {
        models.first { $0.id == id }?.short ?? id
    }

    static func stream(
        apiKey: String, model: String, system: String, user: String, maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "system": system,
                        "messages": [["role": "user", "content": user]],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw ClaudeError(message: Claude.errorMessage(status: status, data: data))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                        else { continue }

                        switch event["type"] as? String {
                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any], let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "error":
                            let info = event["error"] as? [String: Any]
                            throw ClaudeError(message: (info?["message"] as? String) ?? "The API returned an error.")
                        case "message_stop":
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(status: Int, data: Data) -> String {
        let apiMessage = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["message"] as? String }
        switch status {
        case 401: return "Your API key was rejected. Check it in Settings (⌘,)."
        case 403: return "This API key doesn't have access to that model."
        case 404: return "Model not found. Pick a different model in Settings."
        case 429: return "Rate limited. Wait a moment and press ⌘R."
        case 529: return "Claude is overloaded right now. Press ⌘R to try again."
        default: return apiMessage ?? "Request failed (HTTP \(status))."
        }
    }
}
