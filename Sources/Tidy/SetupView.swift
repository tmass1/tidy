import TidyCore
import AppKit
import SwiftUI

// Setup stays in the panel: connection, selection access, shortcut, then an optional live sample.
// Success waits for Continue. General › More options › Review setup opens it again.
// Esc steps back, then closes; the existing global shortcut still advances practice.

enum SetupStep: Int, CaseIterable {
    case key, access, shortcut, tryIt
    var title: String {
        switch self {
        case .key: return "Connection"
        case .access: return "Selection access"
        case .shortcut: return "Shortcut"
        case .tryIt: return "Start writing"
        }
    }

    /// The practice draft on the last step.
    static let sample = "hey can u look over the deck before tmrw, i think slide 4 is confusing and the numbers on 7 dont match the q3 report"
}

struct SetupPage: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
            Group {
                switch model.setupStep {
                case .key: KeyStep(model: model, store: store)
                case .access: AccessStep(model: model, store: store)
                case .shortcut: ShortcutStep(model: model, store: store)
                case .tryIt: TryStep(model: model, store: store)
                }
            }
            .id(model.setupStep)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 14)), removal: .opacity))
        }
        .padding(EdgeInsets(top: 12, leading: 30, bottom: 22, trailing: 30))
        .frame(minHeight: 452, alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.setupStep)
    }

    /// "Setup · 2 of 4" and four short bars, lavender up to the current step.
    private var progress: some View {
        HStack(spacing: 12) {
            Caption(text: "\(model.setupStep.title) · \(model.setupStep.rawValue + 1) of \(SetupStep.allCases.count)")
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(SetupStep.allCases, id: \.self) { step in
                    Capsule()
                        .fill(Color(step.rawValue <= model.setupStep.rawValue ? Theme.accent : Theme.rule))
                        .frame(width: 26, height: 3)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.bottom, 26)
    }
}

// MARK: - Steps

private struct KeyStep: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store

    var body: some View {
        SetupLayout(symbol: store.hasAPIKey ? "checkmark.circle" : "key",
                    title: store.hasAPIKey ? "Your key is saved." : "Connect Tidy.",
                    detail: store.hasAPIKey ? "Your connection is set up. Next, choose whether Tidy can read selected text and paste back a rewrite." : "Use your Anthropic API key, just like on iPhone. No new Tidy account needed.") {
            KeyConnectionEditor(store: store)
        } footer: {
            Spacer(minLength: 0)
            LensButton(title: "Continue to Accessibility", prominent: true) { model.setupStep = .access }
                .disabled(!store.hasAPIKey)
        }
    }
}

private struct AccessStep: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @State private var trusted: Bool
    init(model: PanelModel, store: Store) {
        self.model = model; self.store = store
        _trusted = State(initialValue: store.accessibilityAllowed())
    }
    @State private var asked = false

    var body: some View {
        SetupLayout(
            symbol: "hand.raised",
            title: "Let Tidy copy and paste for you",
            detail: "Tidy presses ⌘C to read what you selected and ⌘V to put the new version back. macOS asks you to allow that once."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if trusted {
                    StatusDot(text: "Allowed. Tidy can read your selection and paste the result.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        instruction(1, "Open System Settings")
                        instruction(2, "Turn on Tidy under Privacy & Security › Accessibility")
                        instruction(3, "Come back to Tidy and choose Continue.")
                    }
                    HStack(spacing: 14) {
                        LensButton(title: "Open System Settings…", prominent: true, action: open)
                        if asked {
                            ShimmerText(text: Text("Waiting for Accessibility…").font(.system(size: 12)), base: Color(Theme.muted))
                                .lineBox(12)
                        }
                    }
                }
            }
        } footer: {
            SmallButton(title: "Back", symbol: "arrow.left") { model.setupStep = .key }
                .padding(.leading, -6)
            Spacer(minLength: 0)
            if trusted {
                LensButton(title: "Continue", prominent: true) { model.setupStep = .shortcut }
            } else {
                SmallButton(title: "Skip for now") { model.setupStep = .shortcut }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = store.accessibilityAllowed()
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(Theme.accent))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(Theme.accentSoft)))
            Text(text).font(.system(size: 13)).lineBox(13)
        }
    }

    /// The first time, macOS's own prompt (which also adds Tidy to the list); after that, straight
    /// to the Accessibility pane.
    private func open() {
        if asked {
            Selection.openAccessibilitySettings()
        } else {
            _ = Selection.isTrusted(prompt: true)
        }
        asked = true
    }
}

private struct ShortcutStep: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store

    var body: some View {
        SetupLayout(
            symbol: "command",
            title: "Your shortcut",
            detail: "Select text in any app, then press it. Tidy opens over that app, and ⌘↩ puts the new version back."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Keycaps(shortcut: store.shortcut)
                if store.hotKeyRegistered {
                    Text(store.isDesignPreview ? "Use Continue in this preview. Your global shortcut is unchanged." : "Press it now to try it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(Theme.accent))
                        .lineBox(12)
                } else {
                    StatusDot(text: "Another app already uses \(store.shortcut.display). Pick a different one.", isError: true)
                }
                HStack(spacing: 10) {
                    Text("Prefer a different one?")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(Theme.muted))
                    ShortcutRecorder(store: store)
                }
            }
        } footer: {
            SmallButton(title: "Back", symbol: "arrow.left") { model.setupStep = .access }
                .padding(.leading, -6)
            Spacer(minLength: 0)
            LensButton(title: store.hotKeyRegistered ? "Continue" : "Continue without shortcut", prominent: true) { model.setupStep = .tryIt }
        }
    }
}

private struct TryStep: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    private var readiness: SetupReadiness {
        SetupReadiness(hasKey: store.hasAPIKey, hasAccess: store.accessibilityAllowed(), hasShortcut: store.hotKeyRegistered)
    }

    var body: some View {
        SetupLayout(
            symbol: "wand.and.stars",
            title: readiness == .ready ? "Ready for your first cleanup." : "Start with a pasted draft.",
            detail: store.isDesignPreview ? "Use Rewrite sample to try a recorded response, or Start writing to leave the walkthrough. This preview does not register your global shortcut." : readiness == .ready
                ? "Choose Start writing to leave setup, then select text in another app and press \(store.shortcut.display). While you’re here, the shortcut rewrites this sample."
                : "Choose Start writing, then paste a draft into Tidy. \(readiness.detail)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.isDesignPreview ? "Sample draft · recorded preview" : "Sample draft · uses your Anthropic API key")
                    .font(.system(size: 12)).foregroundStyle(Color(Theme.accent)).lineBox(12)
                Text(sample)
                .font(.system(size: 17))
                .tracking(-0.3)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(Theme.well)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(Theme.wellBorder), lineWidth: 1))
                Text(store.isDesignPreview ? "This design preview makes no API requests." : "This is a live rewrite. API usage is billed to your Anthropic account.")
                    .font(.system(size: 12)).foregroundStyle(Color(Theme.muted)).lineBox(12)
            }
        } footer: {
            SmallButton(title: "Back", symbol: "arrow.left") { model.setupStep = .shortcut }
                .padding(.leading, -6)
            Spacer(minLength: 0)
            SmallButton(title: "Start writing") { model.skipSetup() }
            LensButton(title: "Rewrite sample", prominent: true) { model.tryOnSample() }
        }
    }

    /// The draft with a selection highlight, as if you'd just selected it.
    private var sample: AttributedString {
        var text = AttributedString(SetupStep.sample)
        text.backgroundColor = Color(Theme.accent).opacity(0.22)
        return text
    }
}

// MARK: - Parts

/// One step: a tinted icon, a title, a sentence or two, the step's controls, and its buttons
/// along the bottom.
private struct SetupLayout<Content: View, Footer: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Color(Theme.accent))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color(Theme.accentSoft)))
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: Theme.prose.size))
                .tracking(Theme.prose.kern)
                .lineBox(Theme.prose.size)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Color(Theme.muted))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.bottom, 24)
            content
            Spacer(minLength: 24)
            HStack(spacing: 10) { footer }
                .padding(.top, 14)
                .overlay(alignment: .top) { Rule() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The shortcut as large keycaps: ⌥ ⌘ C.
private struct Keycaps: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: 22, weight: .medium))
                    .frame(minWidth: 52, minHeight: 52)
                    .padding(.horizontal, part.count > 1 ? 10 : 0)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(Theme.well)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(Theme.wellBorder), lineWidth: 1))
                    .shadow(color: Color(Theme.shadow), radius: 0, y: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(shortcut.display)")
    }

    /// "⌥⌘C" → ["⌥", "⌘", "C"]; a named key like "Space" stays whole.
    private var parts: [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let display = shortcut.display
        let mods = display.prefix { modifiers.contains($0) }.map(String.init)
        return mods + [String(display.dropFirst(mods.count))]
    }
}
