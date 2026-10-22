import AppKit
import SwiftUI

/// Lens design tokens, taken from the approved UI handoff (styles.css + glass-finish.css).
/// Every color adapts to light and dark mode. CSS px map 1:1 to points.
enum Theme {
    // MARK: Colors

    static let ink = dynamic("#292832", "#f0eef7")
    static let muted = dynamic("#74717f", "#b6b1c4")
    static let rule = dynamic("#aca2bd30", "#b9aaca25")
    static let layer = dynamic("#ecebf4b3", "#36323fa8") // hover
    static let soft = dynamic("#f0edf780", "#302b3c80") // command bar
    static let accent = dynamic("#6350c5", "#bcabff")
    static let accentSoft = dynamic("#eee9ff", "#393047")
    static let action = dynamic("#292832", "#eeebf6")
    static let onAction = dynamic("#ffffff", "#282432")
    static let green = dynamic("#286248", "#a3d8b9")
    static let greenWash = dynamic("#e7f3eb", "#273e33")
    static let greenLine = dynamic("#28624866", "#a3d8b966") // green at 40%
    static let red = dynamic("#a54b56", "#f1afb7")
    static let redWash = dynamic("#f9e9ed", "#472f36")
    static let shadow = dynamic("#27203622", "#00000060")

    // Glass surface: 87% paper over a blurred backdrop, a faint diagonal reflection, a fine rim.
    static let glass = dynamic("#fcfcffde", "#26252ede")
    static let opaque = dynamic("#fcfcff", "#282730") // reduced transparency
    static let reflection = dynamic("#ffffff35", "#ffffff08")
    static let rim = dynamic("#ffffffc7", "#ffffff29")
    static let innerRim = dynamic("#ffffff26", "#ffffff03")
    static let topHighlight = dynamic("#ffffffc7", "#ffffff14")

    // MARK: Type

    /// 650 in CSS sits between semibold (600) and bold (700).
    static let brandWeight = NSFont.Weight(rawValue: 0.35)
    /// 550 in CSS sits between medium (500) and semibold (600).
    static let actionWeight = NSFont.Weight(rawValue: 0.27)

    /// The main text: 23 pt, line height 1.53, tracking −0.65.
    static let prose = Prose(size: 23, lineHeight: 1.53, kern: -0.65)
    /// Changes view: 18 pt, line height 1.85, tracking −0.25.
    static let diff = Prose(size: 18, lineHeight: 1.85, kern: -0.25)

    struct Prose {
        let size: CGFloat
        let lineHeight: CGFloat
        let kern: CGFloat

        var font: NSFont { .systemFont(ofSize: size) }

        /// Attributes that reproduce CSS line-height: a fixed line box with the glyphs
        /// centred in it (half-leading above and below), rather than AppKit's default of
        /// pushing all the extra space above the text.
        func attributes(color: NSColor = Theme.ink) -> [NSAttributedString.Key: Any] {
            let font = self.font
            let box = (size * lineHeight).rounded(.toNearestOrAwayFromZero)
            let natural = font.ascender - font.descender + font.leading
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = box
            paragraph.maximumLineHeight = box
            return [
                .font: font,
                .foregroundColor: color,
                .kern: kern,
                .paragraphStyle: paragraph,
                .baselineOffset: ((box - natural) / 2).rounded(),
            ]
        }
    }

    // MARK: Helpers

    static func dynamic(_ light: String, _ dark: String) -> NSColor {
        let l = hex(light), d = hex(dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? d : l
        }
    }

    private static func hex(_ s: String) -> NSColor {
        var v: UInt64 = 0
        Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
        let hasAlpha = s.count == 9
        let rgba = hasAlpha ? v : (v << 8 | 0xff)
        return NSColor(
            srgbRed: CGFloat((rgba >> 24) & 0xff) / 255,
            green: CGFloat((rgba >> 16) & 0xff) / 255,
            blue: CGFloat((rgba >> 8) & 0xff) / 255,
            alpha: CGFloat(rgba & 0xff) / 255
        )
    }
}

extension Color {
    init(_ ns: NSColor) { self.init(nsColor: ns) }
}
