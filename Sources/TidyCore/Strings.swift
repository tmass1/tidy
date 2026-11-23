import Foundation

public extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var wordCount: Int { split(whereSeparator: { $0.isWhitespace }).count }
    var firstLine: String {
        split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }
}
