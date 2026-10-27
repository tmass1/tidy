import AppKit
import SwiftUI

// The panel's Settings page: every setting, in tabs (General, Modes, Voice, History). It replaces
// everything under the title bar; "Back to text" (or Esc) returns to the editor as it was.
// The tab contents live in SettingsView.swift.

struct SettingsPage: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    let maxHeight: CGFloat

    var body: some View {
        PageScroll(maxHeight: maxHeight) {
            BackButton(title: "Back to text") { model.page = .editor }
            HStack(spacing: 15) {
                tab("General", .general)
                tab("Modes", .modes)
                tab("Voice", .voice)
                tab("History", .history)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
            switch store.settingsTab {
            case .general: GeneralTab(store: store) { model.openSetup() }
            case .modes: ModesTab(store: store)
            case .voice: VoiceTab(store: store)
            case .history: HistoryTab(model: model, store: store)
            }
        }
    }

    private func tab(_ title: String, _ value: SettingsTab) -> some View {
        ViewTab(title: title, selected: store.settingsTab == value) {
            store.settingsTab = value
            model.historySelection = nil
        }
    }
}

/// How a history entry is described in lists and headers.
enum HistoryText {
    /// "Mail · Today, 10:42 AM"
    static func caption(for item: HistoryItem) -> String {
        let when = "\(dayFormatter.string(from: item.date)), \(timeFormatter.string(from: item.date))"
        return [item.app, when].compactMap { $0 }.joined(separator: " · ")
    }

    /// The row title is the first line, skipping a short greeting like "Hey Maya,";
    /// the snippet is what follows it.
    static func titleAndSnippet(_ text: String) -> (title: String, snippet: String) {
        var lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.count > 1, let first = lines.first, first.hasSuffix(","), first.wordCount <= 4 {
            lines.removeFirst()
        }
        return (lines.first ?? "", lines.dropFirst().joined(separator: " "))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

/// A history entry: when and where, the first line, then a snippet.
struct HistoryRow: View {
    let item: HistoryItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let text = HistoryText.titleAndSnippet(item.sent)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(HistoryText.caption(for: item) + (item.edited ? " · edited" : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(Theme.muted))
                    .lineBox(11)
                Text(text.title)
                    .font(Font(NSFont.systemFont(ofSize: 16, weight: .medium) as CTFont))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .lineBox(16)
                    .padding(.vertical, 6)
                if !text.snippet.isEmpty {
                    Text(text.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(Theme.muted))
                        .lineLimit(1)
                        .lineBox(12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.bottom, 1)
            .background(hovering ? Color(Theme.layer) : .clear)
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the full text")
    }
}

/// The model choice: a quiet menu showing "Sonnet 5.5", with the full names inside.
struct ModelMenu: View {
    @ObservedObject var store: Store

    var body: some View {
        Menu {
            ForEach(Claude.models) { option in
                Button {
                    store.model = option.id
                } label: {
                    if option.id == store.model {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            Text(Self.label(for: store.model))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(Theme.layer)))
        .accessibilityLabel("Writing model")
    }

    /// "Sonnet 5.5 · balanced" → "Sonnet 5.5"
    static func label(for id: String) -> String {
        let name = Claude.models.first { $0.id == id }?.name ?? id
        return name.components(separatedBy: " · ").first ?? name
    }
}

/// A settings row: title and muted detail on the left, a control on the right, a rule below.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    var detailIsError = false
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).lineBox(13)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(detailIsError ? Theme.red : Theme.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineBox(12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.vertical, 16)
        .padding(.bottom, 1)
        .overlay(alignment: .bottom) { Rule() }
    }
}

struct CheckboxRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(LensCheckbox(label: title))
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// A 17 pt checkbox in the accent color, as in the design.
struct LensCheckbox: ToggleStyle {
    let label: String

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        return Button {
            configuration.isOn.toggle()
        } label: {
            shape
                .fill(configuration.isOn ? Color(Theme.accent) : .clear)
                .overlay(shape.strokeBorder(configuration.isOn ? .clear : Color(Theme.muted), lineWidth: 1))
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(Theme.onAction))
                    }
                }
                .frame(width: 17, height: 17)
        }
        .buttonStyle(BareButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Shared page pieces

/// Page padding (16 / 30 / 26), at least 431 pt tall, scrolling past `maxHeight`.
private struct PageScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(EdgeInsets(top: 16, leading: 30, bottom: 26, trailing: 30))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: PageHeightKey.self, value: proxy.size.height)
                })
        }
        .onPreferenceChange(PageHeightKey.self) { height = $0 }
        .frame(height: min(max(height, 431), maxHeight))
    }
}

private struct PageHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        SmallButton(title: title, symbol: "arrow.left", action: action)
            .padding(.leading, -6)
            .help("Esc")
    }
}

/// A quiet text button (muted, hover fill): back links, Reset, Copy. Red when destructive.
struct SmallButton: View {
    let title: String
    var symbol: String?
    var destructive = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11))
                }
                Text(title).lineBox(13)
            }
            .foregroundStyle(Color(destructive ? Theme.red : hovering ? Theme.ink : Theme.muted))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering && isEnabled ? Color(Theme.layer) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
    }
}

struct Rule: View {
    var body: some View {
        Rectangle().fill(Color(Theme.rule)).frame(height: 1)
    }
}

/// The lower-case "tidy" wordmark: 21 pt, weight 650, tracking −1.
struct Wordmark: View {
    var body: some View {
        Text("tidy")
            .font(Font(NSFont.systemFont(ofSize: 21, weight: Theme.brandWeight) as CTFont))
            .tracking(-1)
            .lineBox(21)
            .accessibilityLabel("Tidy")
    }
}

/// Muted 11 pt label above a field or block, like the design's detail labels.
struct Caption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(Theme.muted))
            .lineBox(11)
    }
}

/// A borderless text field with a hairline underneath that turns lavender while focused.
struct LensField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text, prompt: prompt)
            } else {
                TextField(placeholder, text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .focused($focused)
        .onAppear { if autofocus { focused = true } }
        .lineBox(13)
        .padding(.vertical, 8)
        .padding(.bottom, 1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(focused ? Theme.accent : Theme.rule)).frame(height: 1)
        }
    }

    private var prompt: Text { Text(placeholder).foregroundColor(Color(Theme.muted)) }
}

/// A compact text button. Prominent uses the replace action's colors (dark in light mode,
/// pale in dark mode); otherwise a quiet tinted fill.
struct LensButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Font(NSFont.systemFont(ofSize: 12, weight: Theme.actionWeight) as CTFont))
                .lineBox(12)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .foregroundStyle(Color(prominent ? Theme.onAction : Theme.ink))
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(prominent ? Theme.action : Theme.layer))
                        .brightness(hovering && isEnabled ? 0.04 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
    }
}
