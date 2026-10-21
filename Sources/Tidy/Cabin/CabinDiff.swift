// Copied from Cabin 0.23.0 (tmass1/cabin, swift/Sources/CabinKit) by scripts/swift.mjs --sync. Don't edit here: change Cabin, then sync.
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// What changed between two versions of a piece of text, word by word: Cabin's `Diff`, for native apps.
/// Removed words are struck through and added ones underlined, each on a faint tint of its tone, so it reads
/// without colour. Show it before the person accepts a change.
public enum CabinDiff {
    public enum Kind: Sendable, Equatable { case same, add, del, gap }

    public struct Part: Sendable, Equatable {
        public var kind: Kind
        public var text: String
        public init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
    }

    /// Words (letters, digits and apostrophes), runs of whitespace, and each other character on its own.
    public static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var currentClass = -1
        for ch in s {
            let cls = ch.isWhitespace ? 0 : (ch.isLetter || ch.isNumber || ch == "'" || ch == "’") ? 1 : 2
            if cls == currentClass && cls != 2 {
                current.append(ch)
            } else {
                if !current.isEmpty { out.append(current) }
                current = String(ch)
                currentClass = cls
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// The diff as runs of same, added and removed text. A lone space between two changes is a `.gap`: it reads as
    /// part of the change. Very long texts (over 4 million token pairs) come back as one removal and one addition.
    public static func parts(before: String, after: String) -> [Part] {
        let a = tokens(before), b = tokens(after), n = a.count, m = b.count
        if n * m > 4_000_000 { return [Part(.del, before), Part(.add, after)] }
        let w = m + 1
        var lcs = [Int32](repeating: 0, count: (n + 1) * w)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i * w + j] = a[i] == b[j] ? lcs[(i + 1) * w + j + 1] + 1 : max(lcs[(i + 1) * w + j], lcs[i * w + j + 1])
                }
            }
        }
        var out: [Part] = []
        func push(_ kind: Kind, _ text: String) {
            if let last = out.last, last.kind == kind { out[out.count - 1].text += text } else { out.append(Part(kind, text)) }
        }
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { push(.same, a[i]); i += 1; j += 1 }
            else if lcs[(i + 1) * w + j] >= lcs[i * w + j + 1] { push(.del, a[i]); i += 1 }
            else { push(.add, b[j]); j += 1 }
        }
        while i < n { push(.del, a[i]); i += 1 }
        while j < m { push(.add, b[j]); j += 1 }
        if out.count > 2 {
            for k in 1..<(out.count - 1) where out[k].kind == .same
                && out[k].text.allSatisfy({ $0.isWhitespace })
                && out[k - 1].kind != .same && out[k + 1].kind != .same {
                out[k].kind = .gap
            }
        }
        return out
    }

    /// How many places changed ("6 changes"): each run of removals and additions counts once.
    public static func changeCount(_ parts: [Part]) -> Int {
        var count = 0, inChange = false
        for p in parts {
            switch p.kind {
            case .add, .del: if !inChange { count += 1; inChange = true }
            case .same: inChange = false
            case .gap: break
            }
        }
        return count
    }
}

#if canImport(AppKit)
extension CabinDiff {
    public enum Style: Sendable { case inline, after }

    /// The diff as an attributed string for an NSTextView or SwiftUI Text: removals struck through in muted text on a
    /// destructive tint, additions underlined on a success tint, a thin space between a removal and what replaced it.
    public static func attributed(before: String, after: String, style: Style = .inline,
                                  font: NSFont = .systemFont(ofSize: 14), lineSpacing: CGFloat = 3) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Cabin.NS.foreground, .paragraphStyle: paragraph]
        var removed = base
        removed[.foregroundColor] = Cabin.NS.mutedForeground
        removed[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        removed[.strikethroughColor] = Cabin.NS.destructive
        removed[.backgroundColor] = Cabin.tint(Cabin.Values.destructiveFill, 0.14)
        var added = base
        added[.underlineStyle] = NSUnderlineStyle.single.rawValue
        added[.underlineColor] = Cabin.NS.success
        added[.backgroundColor] = Cabin.tint(Cabin.Values.successFill, 0.22)

        let out = NSMutableAttributedString()
        var previous: Kind?
        for part in parts(before: before, after: after) {
            let blank = part.text.allSatisfy { $0.isWhitespace }
            switch part.kind {
            case .same, .gap:
                out.append(NSAttributedString(string: part.text, attributes: base))
            case .del:
                if style == .after || blank { continue }
                if previous == .add { out.append(NSAttributedString(string: "\u{2009}", attributes: base)) }
                out.append(NSAttributedString(string: part.text, attributes: removed))
            case .add:
                if previous == .del && style == .inline { out.append(NSAttributedString(string: "\u{2009}", attributes: base)) }
                out.append(NSAttributedString(string: part.text, attributes: blank ? base : added))
            }
            previous = part.kind
        }
        return out
    }
}
#endif
