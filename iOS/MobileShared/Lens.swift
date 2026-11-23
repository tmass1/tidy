import SwiftUI
import TidyCore

/// Exact RGB pairs from the Mac Theme; typography uses scalable native text styles.
enum Lens {
    static let ink = color(0x292832, 0xf0eef7)
    static let muted = color(0x74717f, 0xb6b1c4)
    static let paper = color(0xfcfcff, 0x282730)
    static let well = color(0xf0edf7, 0x211f28)
    static let accent = color(0x6350c5, 0xbcabff)
    static let accentSoft = color(0xeee9ff, 0x393047)
    static let action = color(0x292832, 0xeeebf6)
    static let onAction = color(0xffffff, 0x282432)
    static let red = color(0xa54b56, 0xf1afb7)
    static let green = color(0x286248, 0xa3d8b9)
    static let redWash = color(0xf9e9ed, 0x472f36)
    static let greenWash = color(0xe7f3eb, 0x273e33)
    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let n = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
        })
    }
    static func changes(original: String, result: String) -> AttributedString? {
        guard let chunks = WordDiff.diff(original, result) else { return nil }
        var output = AttributedString()
        var previous = WordDiff.Op.same
        for chunk in chunks {
            if previous != .same && chunk.op != .same && previous != chunk.op {
                output.append(AttributedString("\u{2009}"))
            }
            var part = AttributedString(chunk.text)
            switch chunk.op {
            case .same: part.foregroundColor = ink
            case .del: part.foregroundColor = red; part.backgroundColor = redWash; part.strikethroughStyle = .single
            case .ins: part.foregroundColor = green; part.backgroundColor = greenWash; part.underlineStyle = .single
            }
            output.append(part)
            previous = chunk.op
        }
        return output
    }
}

struct LensPrimary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(Lens.onAction).background(Lens.action, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
