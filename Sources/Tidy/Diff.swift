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

/// Attributed strings for the result area.
enum Styled {
    static var base: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    static func plain(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: base)
    }

    static func diff(from original: String, to result: String) -> NSAttributedString {
        guard !result.isEmpty else { return plain("") }
        guard let chunks = WordDiff.diff(original, result) else { return plain(result) }
        let out = NSMutableAttributedString()
        for chunk in chunks {
            var attrs = base
            let isBlank = chunk.text.trimmed.isEmpty
            switch chunk.op {
            case .same:
                break
            case .del:
                if isBlank { continue } // a removed line break or space: just leave it out
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = NSColor.systemRed.withAlphaComponent(0.7)
                attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.13)
            case .ins:
                if !isBlank {
                    attrs[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.22)
                }
            }
            out.append(NSAttributedString(string: chunk.text, attributes: attrs))
        }
        return out
    }
}
