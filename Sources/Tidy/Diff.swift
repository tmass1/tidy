import AppKit

/// Word-level diff (longest common subsequence over words and the whitespace between them).
enum WordDiff {
    enum Op { case same, del, ins }

    struct Chunk {
        let op: Op
        var text: String
    }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var currentIsSpace: Bool?
        for ch in s {
            let isSpace = ch.isWhitespace
            if currentIsSpace == isSpace {
                current.append(ch)
            } else {
                if !current.isEmpty { out.append(current) }
                current = String(ch)
                currentIsSpace = isSpace
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func diff(_ a: String, _ b: String) -> [Chunk]? {
        let A = tokens(a), B = tokens(b)
        let n = A.count, m = B.count
        guard n * m <= 2_500_000 else { return nil }

        let w = m + 1
        var dp = [Int32](repeating: 0, count: (n + 1) * w)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i * w + j] = A[i] == B[j]
                        ? dp[(i + 1) * w + j + 1] + 1
                        : max(dp[(i + 1) * w + j], dp[i * w + j + 1])
                }
            }
        }

        var chunks: [Chunk] = []
        func push(_ op: Op, _ text: String) {
            if let last = chunks.last, last.op == op {
                chunks[chunks.count - 1].text += text
            } else {
                chunks.append(Chunk(op: op, text: text))
            }
        }
        var i = 0, j = 0
        while i < n && j < m {
            if A[i] == B[j] {
                push(.same, A[i]); i += 1; j += 1
            } else if dp[(i + 1) * w + j] >= dp[i * w + j + 1] {
                push(.del, A[i]); i += 1
            } else {
                push(.ins, B[j]); j += 1
            }
        }
        while i < n { push(.del, A[i]); i += 1 }
        while j < m { push(.ins, B[j]); j += 1 }
        return chunks
    }
}

/// Attributed strings for the panel's text areas.
enum Styled {
    /// The main text (Final, streaming and the held original).
    static func prose(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: Theme.prose.attributes())
    }

    /// Where a streamed chunk ends (UTF-16 offset into the text) and when it arrived.
    struct Arrival {
        let end: Int
        let time: Date
    }

    /// The text while it streams: each chunk fades in over `fade` seconds after it arrives,
    /// so new words settle onto the page instead of popping in.
    static func streaming(_ s: String, arrivals: [Arrival], now: Date, fade: TimeInterval) -> NSAttributedString {
        let out = NSMutableAttributedString(string: s, attributes: Theme.prose.attributes())
        let length = out.length
        // Newest first; everything older than `fade` is already fully inked.
        for index in arrivals.indices.reversed() {
            let progress = now.timeIntervalSince(arrivals[index].time) / fade
            guard progress < 1 else { break }
            let start = index > 0 ? min(arrivals[index - 1].end, length) : 0
            let end = min(arrivals[index].end, length)
            guard end > start else { continue }
            let eased = 1 - pow(1 - max(progress, 0), 2)
            out.addAttribute(
                .foregroundColor, value: Theme.ink.withAlphaComponent(0.1 + 0.9 * eased),
                range: NSRange(location: start, length: end - start)
            )
        }
        return out
    }

    /// Changes: removals in red with a strikethrough, additions in green with an underline,
    /// so color is never the only signal.
    static func diff(from original: String, to result: String) -> NSAttributedString {
        let base = Theme.diff.attributes()
        guard !result.isEmpty else { return NSAttributedString(string: "", attributes: base) }
        guard let chunks = WordDiff.diff(original, result) else {
            return NSAttributedString(string: result, attributes: base)
        }
        let out = NSMutableAttributedString()
        var previous: WordDiff.Op = .same
        for chunk in chunks {
            var attrs = base
            let isBlank = chunk.text.trimmed.isEmpty
            switch chunk.op {
            case .same:
                break
            case .del:
                if isBlank { continue } // a removed line break or space: just leave it out
                attrs[.foregroundColor] = Theme.red
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = Theme.red
                attrs[.backgroundColor] = Theme.redWash
            case .ins:
                if !isBlank {
                    attrs[.foregroundColor] = Theme.green
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attrs[.underlineColor] = Theme.greenLine
                    attrs[.backgroundColor] = Theme.greenWash
                }
            }
            // A removal right next to an addition gets a 4 pt gap so the two don't read as one
            // word. The gap is a zero-width space so the highlight backgrounds don't stretch over it.
            if previous != .same && chunk.op != .same && previous != chunk.op {
                var gap = base
                gap[.kern] = Theme.diff.kern + 4
                out.append(NSAttributedString(string: "\u{200B}", attributes: gap))
            }
            // A removed line break isn't in the result, so show it as a space. Line breaks inside a
            // change keep the plain style, or their highlight would run on to the margin.
            let text = chunk.op == .del ? chunk.text.replacingOccurrences(of: "\n", with: " ") : chunk.text
            let piece = NSMutableAttributedString(string: text, attributes: attrs)
            if chunk.op == .ins {
                let ns = text as NSString
                var location = 0
                while location < ns.length {
                    let found = ns.rangeOfCharacter(from: .newlines, range: NSRange(location: location, length: ns.length - location))
                    if found.location == NSNotFound { break }
                    piece.setAttributes(base, range: found)
                    location = NSMaxRange(found)
                }
            }
            out.append(piece)
            previous = chunk.op
        }
        return out
    }
}
