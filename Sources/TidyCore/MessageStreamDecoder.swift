import Foundation

/// Strict completion tracking for clients that must distinguish a partial response.
struct MessageStreamDecoder {
    private(set) var completed = false
    mutating func consume(_ line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError(message: "Claude returned an unreadable response. Try again.")
        }
        switch event["type"] as? String {
        case "content_block_delta":
            return (event["delta"] as? [String: Any])?["text"] as? String
        case "message_delta":
            if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String,
               reason == "max_tokens" || reason == "refusal" {
                throw ClaudeError(message: reason == "max_tokens"
                    ? "The response reached its length limit. Try a shorter message."
                    : "Claude could not rewrite this message. Try changing the text.")
            }
        case "message_stop": completed = true
        case "error":
            throw ClaudeError(message: ((event["error"] as? [String: Any])?["message"] as? String) ?? "The API returned an error.")
        default: break
        }
        return nil
    }
    mutating func finish() throws {
        guard completed else { throw ClaudeError(message: "The connection ended before the rewrite finished. Try again.") }
    }
}
