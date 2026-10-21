import Foundation

enum Prompts {
    static func system(voice: String?) -> String {
        var s = """
        You are an editor for messages the user is about to send: emails, texts, Slack and chat messages. \
        Rewrite the message they give you according to the instruction, and return only the finished message.

        Rules:
        - Keep the meaning and every fact, name, number, date, time, link and commitment exactly as given. \
        Never invent details, add promises, or change who is doing what.
        - Keep the format: line breaks, paragraphs, lists, and the greeting and sign-off if there are any. \
        Don't add a subject line, greeting or sign-off that isn't there.
        - Write as the user, in the first person, to the same recipient.
        - Match the medium: a text message stays short and casual; an email can be fuller.
        - If the message is already good, change only what needs changing.
        - Output only the revised message. No preamble, no explanation, no quotation marks around it, \
        no markdown formatting, no code fences, no XML tags.
        """
        if let voice = voice?.trimmed, !voice.isEmpty {
            s += "\n\nHow this person writes. Match it; it takes priority over generic polish:\n" + voice
        }
        return s
    }

    static func user(text: String, instruction: String, app: String?) -> String {
        var s = "Instruction: \(instruction)\n"
        if let app { s += "Being written in: \(app)\n" }
        s += "\n<message>\n\(text)\n</message>"
        return s
    }

    static func tweakInstruction(_ tweak: String) -> String {
        "Keep the message as it is, except make this change: \(tweak)"
    }

    /// Strips wrappers the model sometimes adds (tags, code fences), safely mid-stream.
    static func clean(_ raw: String, streaming: Bool) -> String {
        let openTag = "<message>"
        var s = String(raw.drop(while: { $0.isWhitespace }))
        if s.hasPrefix(openTag) {
            s = String(s.dropFirst(openTag.count))
        } else if streaming && openTag.hasPrefix(s) {
            return ""
        }
        if s.hasPrefix("```") {
            if let newline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: newline)...])
            } else if streaming {
                return ""
            }
        }
        s = String(s.drop(while: { $0 == "\n" }))
        if let close = s.range(of: "</message>") { s = String(s[..<close.lowerBound]) }
        if !streaming {
            s = s.trimmed
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
            s = s.trimmed
        }
        return s
    }

    // MARK: - Voice learning

    static let voiceSystem = """
    You maintain a short profile of how one specific person writes. An editing assistant reads it \
    so that cleaned-up messages still sound like that person. Describe only patterns the evidence supports.
    """

    static func voiceLearn(current: String, edits: [HistoryItem], drafts: [String], samples: String?) -> String {
        var s = "Update the writing-voice profile below using the new evidence.\n\n"
        s += "Current profile:\n" + (current.trimmed.isEmpty ? "(none yet)" : current.trimmed) + "\n\n"

        if !edits.isEmpty {
            s += "Times the person changed the assistant's suggestion before sending it. "
            s += "What they changed is the strongest signal of how they want to sound.\n\n"
            for (i, item) in edits.enumerated() {
                s += "Example \(i + 1)\nAssistant suggested:\n\(item.suggestion)\n\nThey actually sent:\n\(item.sent)\n\n"
            }
        }
        if let samples, !samples.trimmed.isEmpty {
            s += "Messages they wrote themselves:\n\(samples.trimmed)\n\n"
        }
        if !drafts.isEmpty {
            s += "Rough drafts they typed recently (evidence of vocabulary and tone; ignore typos):\n"
            for d in drafts { s += "---\n\(d.trimmed)\n" }
            s += "\n"
        }
        s += """
        Write the updated profile as 5 to 12 short bullet points starting with "- ". Cover, where the \
        evidence shows it: tone and formality, typical length, greetings and sign-offs, punctuation and \
        capitalization habits, words and phrases they use or avoid, and the kinds of changes they keep \
        making to suggestions. Keep useful points from the current profile unless the evidence contradicts \
        them. Output only the bullet points.
        """
        return s
    }
}
