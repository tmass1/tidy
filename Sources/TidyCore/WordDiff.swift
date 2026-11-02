import Foundation

/// Word-level diff (longest common subsequence over words and the whitespace between them).
public enum WordDiff {
    public enum Op { case same, del, ins }

    public struct Chunk {
        public let op: Op
        public var text: String
    }

    public static func tokens(_ s: String) -> [String] {
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

    public static func diff(_ a: String, _ b: String) -> [Chunk]? {
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

