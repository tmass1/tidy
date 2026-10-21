// Copied from Cabin 0.23.0 (tmass1/cabin, swift/Sources/CabinKit) by scripts/swift.mjs --sync. Don't edit here: change Cabin, then sync.
#if canImport(AppKit)
import AppKit

extension Cabin {
    /// A token's colour at a fraction of its strength, for tints behind text: the fraction is raised by half in
    /// light, where a bright colour on white needs more of itself to show (Cabin's --cb-tint).
    public static func tint(_ pair: Pair, _ amount: CGFloat) -> NSColor {
        let light = pair.light, dark = pair.dark
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return Cabin.rgba(isDark ? dark : light).withAlphaComponent(min(1, amount * (isDark ? 1 : 1.45)))
        }
    }
}
#endif

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// A colour family for status: the mark (words, icons, edges), the bright fill, and the ink on that fill.
/// Status never rides on colour alone: pair a tone with a word or an icon.
public enum CabinTone: Sendable, Hashable {
    case neutral, primary, info, success, warning, destructive

    public var mark: Color {
        switch self {
        case .neutral: return Cabin.mutedForeground
        case .primary, .info: return Cabin.info
        case .success: return Cabin.success
        case .warning: return Cabin.warning
        case .destructive: return Cabin.destructive
        }
    }
    public var fill: Color {
        switch self {
        case .neutral: return Cabin.secondary
        case .primary, .info: return Cabin.primary
        case .success: return Cabin.successFill
        case .warning: return Cabin.warningFill
        case .destructive: return Cabin.destructiveFill
        }
    }
    public var onFill: Color {
        switch self {
        case .neutral: return Cabin.secondaryForeground
        case .primary, .info: return Cabin.primaryForeground
        default: return Cabin.fillForeground
        }
    }
    var pair: Cabin.Pair {
        switch self {
        case .neutral: return Cabin.Values.secondary
        case .primary, .info: return Cabin.Values.primary
        case .success: return Cabin.Values.successFill
        case .warning: return Cabin.Values.warningFill
        case .destructive: return Cabin.Values.destructiveFill
        }
    }
    /// The fill at a fraction of its strength (stronger in light), for a soft badge or a notice's wash.
    public func tint(_ amount: CGFloat) -> Color { Color(nsColor: Cabin.tint(pair, amount)) }
}
#endif
