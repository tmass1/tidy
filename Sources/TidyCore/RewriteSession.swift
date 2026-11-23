import Foundation
import Combine

public struct RewriteRequest {
    public let text: String
    public let instruction: String
    public let model: String
    public let voice: String?
    public init(text: String, instruction: String, model: String, voice: String?) {
        self.text = text; self.instruction = instruction; self.model = model; self.voice = voice
    }
}

@MainActor public final class RewriteSession: ObservableObject {
    public enum Phase: Equatable { case idle, streaming, ready, cancelled, failed }
    public typealias Transport = (RewriteRequest) -> AsyncThrowingStream<String, Error>
    @Published public var original = ""
    @Published public var result = ""
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var error: String?
    private let transport: Transport
    public init(transport: @escaping Transport) { self.transport = transport }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastRequest: RewriteRequest?

    public func run(_ request: RewriteRequest) {
        cancel()
        error = nil
        lastRequest = request
        guard !request.text.trimmed.isEmpty, request.text.count <= 20_000 else {
            error = request.text.trimmed.isEmpty ? "Add some text first." : "Keep the message under 20,000 characters."
            phase = .failed
            return
        }
        result = ""
        phase = .streaming
        let token = generation
        // Create the stream synchronously so every run owns its transport immediately.
        let stream = transport(request)
        task = Task { [weak self] in
            var raw = ""
            do {
                for try await chunk in stream {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    raw += chunk
                    guard raw.count <= 80_000 else { throw ClaudeError(message: "The response is too long. Try a shorter message.") }
                    self.result = Prompts.clean(raw, streaming: true)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                let final = Prompts.clean(raw, streaming: false)
                guard !final.isEmpty else { throw ClaudeError(message: "Claude returned an empty response. Try again.") }
                self.result = final
                self.phase = .ready
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.phase = .failed
                self.error = error.localizedDescription
                    .replacingOccurrences(of: "Settings (⌘,)", with: "Settings")
                    .replacingOccurrences(of: "press ⌘R", with: "tap Retry")
                    .replacingOccurrences(of: "Press ⌘R", with: "Tap Retry")
            }
        }
    }
    public func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        if phase == .streaming { phase = .cancelled }
    }
    public func retry() { if let lastRequest { run(lastRequest) } }
    public func reset() {
        cancel(); result = ""; error = nil; phase = .idle; lastRequest = nil
    }
    deinit { task?.cancel() }
}
