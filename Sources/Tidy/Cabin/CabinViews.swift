// Copied from Cabin 0.23.0 (tmass1/cabin, swift/Sources/CabinKit) by scripts/swift.mjs --sync. Don't edit here: change Cabin, then sync.
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

// Cabin's Desk finish for native Mac apps: compact controls, rounded rectangles for pressables and softer ones for
// panels, hairlines instead of drops, solid surfaces, nothing that glows. The system font (SF) at Desk's sizes.

// MARK: - Buttons

/// Desk buttons. `.buttonStyle(.cabin(.primary))` for the one action in a view, `.cabin(.secondary)` (a push button)
/// for the rest, `.cabin(.ghost)` for icon buttons and quiet actions, `.cabin(.destructive)` for the deleting kind.
/// Height follows `.controlSize`: small 24, regular 28, large 32.
public struct CabinButtonStyle: ButtonStyle {
    public enum Variant: Sendable { case primary, secondary, ghost, destructive }
    public var variant: Variant
    public init(_ variant: Variant = .secondary) { self.variant = variant }
    public func makeBody(configuration: Configuration) -> some View {
        CabinButtonBody(label: configuration.label, isPressed: configuration.isPressed, variant: variant)
    }
}

extension ButtonStyle where Self == CabinButtonStyle {
    /// A Desk push button.
    public static var cabin: CabinButtonStyle { CabinButtonStyle(.secondary) }
    /// A Desk button of a given variant.
    public static func cabin(_ variant: CabinButtonStyle.Variant) -> CabinButtonStyle { CabinButtonStyle(variant) }
}

struct CabinButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let variant: CabinButtonStyle.Variant
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    private var height: CGFloat {
        switch controlSize {
        case .mini: return 20
        case .small: return 24
        case .large: return 32
        case .extraLarge: return 40
        default: return 28
        }
    }
    private var fontSize: CGFloat { controlSize == .small || controlSize == .mini ? 12 : 13 }

    private var fill: Color {
        guard isEnabled else { return Cabin.muted }
        switch variant {
        case .primary: return Cabin.primary
        case .secondary: return Cabin.deskControl
        case .ghost: return hovering || isPressed ? Cabin.accent : Color.clear
        case .destructive: return Cabin.destructive
        }
    }
    private var ink: Color {
        guard isEnabled else { return Cabin.mutedForeground }
        switch variant {
        case .primary: return Cabin.primaryForeground
        case .secondary, .ghost: return Cabin.foreground
        case .destructive: return Cabin.destructiveForeground
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Cabin.Radius.deskControl, style: .continuous)
        label
            .font(.system(size: fontSize, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, variant == .ghost ? height * 0.3 : height * 0.45)
            .frame(minWidth: height, minHeight: height)
            .foregroundStyle(ink)
            .background { shape.fill(fill) }
            // Under the pointer or held, a solid control darkens a touch (light) or lifts (dark) toward the text colour.
            .overlay { shape.fill(Cabin.foreground.opacity(variant != .ghost && isEnabled ? (isPressed ? 0.12 : hovering ? 0.06 : 0) : 0)) }
            .overlay { shape.strokeBorder(variant == .secondary && isEnabled ? Cabin.border : Color.clear, lineWidth: 1) }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.16), value: hovering)
    }
}

// MARK: - Keys

/// Keys as keycaps (⌥⌘C), or as plain glyphs inside a button or a menu row (`.plain`), the way a Mac writes them.
public struct CabinKbd: View {
    public enum Style: Sendable { case keycaps, plain }
    let keys: [String]
    let style: Style
    let spoken: String

    public init(_ keys: String, style: Style = .keycaps) {
        self.keys = CabinKeys.split(keys)
        self.style = style
        self.spoken = CabinKeys.spoken(keys)
    }

    public var body: some View {
        Group {
            if style == .plain {
                Text(keys.joined()).font(.system(size: 11, weight: .medium)).opacity(0.72)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Cabin.mutedForeground)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 18, minHeight: 18)
                            .background { RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Cabin.muted) }
                            .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Cabin.border, lineWidth: 1) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Text and small parts

/// A group's small label: uppercase, tracked, muted. Only for labels; a case-sensitive word (pH) goes elsewhere.
public struct CabinLabel: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Cabin.mutedForeground)
    }
}

/// One of a row of choices that switch at once (a panel's modes): the chosen one fills with `primary`.
public struct CabinChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    public init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .frame(height: 24)
                .foregroundStyle(selected ? Cabin.primaryForeground : Cabin.foreground)
                .background { Capsule().fill(selected ? Cabin.primary : hovering ? Cabin.accent : Cabin.secondary) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A short status word on a soft tint of its tone, with an optional SF Symbol: "Allowed", "Not allowed", "Key saved".
public struct CabinBadge: View {
    let text: String
    let tone: CabinTone
    let symbol: String?

    public init(_ text: String, tone: CabinTone = .neutral, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tone.mark) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Cabin.foreground)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background { Capsule().fill(tone == .neutral ? Cabin.secondary : tone.tint(0.2)) }
    }
}

/// The one thing that needs the person: a title, a line of what to do, and the action that fixes it.
/// One at a time; more than one says how many.
public struct CabinNotice<Action: View>: View {
    let tone: CabinTone
    let title: String
    let message: String?
    let action: Action

    public init(_ title: String, message: String? = nil, tone: CabinTone = .warning, @ViewBuilder action: () -> Action) {
        self.title = title
        self.message = message
        self.tone = tone
        self.action = action()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: tone == .destructive ? "xmark.circle" : tone == .success ? "checkmark.circle" : tone == .warning ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(tone.mark)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let message { Text(message).font(.system(size: 12)).foregroundStyle(Cabin.mutedForeground) }
            }
            Spacer(minLength: 8)
            action
        }
        .padding(12)
        .background { RoundedRectangle(cornerRadius: Cabin.Radius.deskPanel, style: .continuous).fill(tone.tint(0.12)) }
        .overlay { RoundedRectangle(cornerRadius: Cabin.Radius.deskPanel, style: .continuous).strokeBorder(tone.tint(0.35), lineWidth: 1) }
    }
}

extension CabinNotice where Action == EmptyView {
    public init(_ title: String, message: String? = nil, tone: CabinTone = .warning) {
        self.init(title, message: message, tone: tone) { EmptyView() }
    }
}

// MARK: - Surfaces

/// A window's ground under Desk: solid `deskGround`, or the system's vibrancy for a panel that floats over other apps.
public struct CabinWindowBackground: View {
    public enum Material: Sendable { case solid, vibrant }
    let material: Material
    public init(_ material: Material = .solid) { self.material = material }
    public var body: some View {
        if material == .solid { Cabin.deskGround } else { CabinVibrancy() }
    }
}

struct CabinVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Cabin's Desk defaults for a window's content: `primary` as the tint (switches, selection, focus) and 13pt text.
    public func cabinDesk() -> some View {
        tint(Cabin.primary).font(.system(size: 13))
    }

    /// A panel: `card` with a `desk-edge` hairline and Desk's panel corner. For the blocks of a window (a draft, a result).
    public func cabinPanel(fill: Color = Cabin.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: Cabin.Radius.deskPanel, style: .continuous)
        return background { shape.fill(fill) }.overlay { shape.strokeBorder(Cabin.deskEdge, lineWidth: 1) }
    }

    /// A field's box: `card` with an `input` hairline (destructive when invalid) and Desk's control corner.
    public func cabinField(invalid: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Cabin.Radius.deskControl, style: .continuous)
        return background { shape.fill(Cabin.card) }.overlay { shape.strokeBorder(invalid ? Cabin.destructive : Cabin.input.opacity(0.55), lineWidth: 1) }
    }

    /// A chrome band (a toolbar, a sidebar, a header): `desk-chrome` with a hairline under it.
    public func cabinChrome() -> some View {
        background(Cabin.deskChrome).overlay(alignment: .bottom) { Rectangle().fill(Cabin.deskEdge).frame(height: 1) }
    }
}
#endif
