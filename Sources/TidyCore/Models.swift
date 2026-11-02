import Foundation

public struct Mode: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var instruction: String

    public init(id: UUID = UUID(), name: String, instruction: String) {
        self.id = id; self.name = name; self.instruction = instruction
    }

    public static var defaults: [Mode] {
        [
            Mode(name: "Clean up", instruction: "Fix spelling, grammar and punctuation, smooth awkward phrasing, and trim wordiness. Keep my voice, my tone and roughly the same length."),
            Mode(name: "Fix only", instruction: "Make the minimum edits needed: fix spelling, grammar, punctuation and obvious typos only. Do not rephrase, reorder or restyle anything else."),
            Mode(name: "Shorter", instruction: "Make it noticeably shorter and more direct while keeping every important point, request and detail. Cut filler, hedging and repetition."),
            Mode(name: "Warmer", instruction: "Make it warmer and friendlier while staying natural. Don't add gushing language, piles of exclamation marks, or emojis that weren't there."),
            Mode(name: "Polished", instruction: "Make it polished and professional, suitable for a client or an executive, without becoming stiff or longer."),
        ]
    }
}

public struct HistoryItem: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var date: Date
    public var app: String?
    public var mode: String
    public var original: String
    public var suggestion: String
    public var sent: String

    public init(id: UUID = UUID(), date: Date, app: String?, mode: String, original: String, suggestion: String, sent: String) {
        self.id = id; self.date = date; self.app = app; self.mode = mode
        self.original = original; self.suggestion = suggestion; self.sent = sent
    }

    public var edited: Bool { !suggestion.isEmpty && sent.trimmed != suggestion.trimmed }
}

