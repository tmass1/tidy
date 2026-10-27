import AppKit
import SwiftUI

// Setup, as a page in the panel: the API key (checked with Anthropic), Accessibility (moves on by
// itself once it's allowed), the shortcut, then a practice cleanup of a sample draft. First launch
// opens it; Settings › General › Run setup opens it again. Esc steps back, then closes.

enum SetupStep: Int, CaseIterable {
    case key, access, shortcut, tryIt

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
                case .access: AccessStep(model: model)
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
            Caption(text: "Setup · \(model.setupStep.rawValue + 1) of \(SetupStep.allCases.count)")
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
    @State private var draft = ""
    @State private var checking = false
    @State private var result: Claude.KeyCheck?

    var body: some View {
        SetupLayout(
            symbol: "key",
            title: "Add your Anthropic API key",
            detail: "Tidy sends your draft straight to Anthropic with your own key, so you pay only for what you use. The key stays in your Keychain. There’s no account and no Tidy server."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    LensField(
                        placeholder: store.hasAPIKey ? "Paste a different key" : "sk-ant-…",
                        text: $draft, secure: true, autofocus: !store.hasAPIKey
                    )
                    .onSubmit(check)
                    LensButton(title: "Check key", prominent: !store.hasAPIKey, action: check)
                        .disabled(draft.trimmed.isEmpty || checking)
                }
                status
                Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(Theme.accent))
            }
        } footer: {
            Spacer(minLength: 0)
            LensButton(title: "Continue", prominent: store.hasAPIKey) { model.setupStep = .access }
                .disabled(!store.hasAPIKey || checking)
        }
    }

    @ViewBuilder private var status: some View {
        if checking {
            ShimmerText(text: Text("Checking with Anthropic…").font(.system(size: 12)), base: Color(Theme.muted))
                .lineBox(12)
        } else {
            switch result {
            case .valid:
                StatusDot(text: "That key works. It’s saved in your Keychain.")
            case .rejected(let message):
                StatusDot(text: message, isError: true)
            case .unreachable(let message):
                HStack(spacing: 10) {
                    StatusDot(text: "Couldn’t check it: \(message)", isError: true)
                    SmallButton(title: "Save anyway") {
                        store.setAPIKey(draft)
                        draft = ""
                        result = nil
                    }
                }
            case nil:
                if store.hasAPIKey {
                    StatusDot(text: "A key is already saved in your Keychain.")
                }
            }
        }
    }

    private func check() {
        let key = draft.trimmed
        guard !key.isEmpty, !checking else { return }
        checking = true
        Task { @MainActor in
            let outcome = await Claude.checkKey(key)
            checking = false
            result = outcome
            guard outcome == .valid else { return }
            store.setAPIKey(key)
            draft = ""
            // A good key moves on by itself after a beat.
            try? await Task.sleep(nanoseconds: 900_000_000)
            if model.page == .setup, model.setupStep == .key { model.setupStep = .access }
        }
    }
}

private struct AccessStep: View {
    @ObservedObject var model: PanelModel
    @State private var trusted = Selection.isTrusted(prompt: false)
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
                        instruction(3, "Come back here. Setup moves on by itself.")
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
            let now = Selection.isTrusted(prompt: false)
            guard now, !trusted else { return }
            trusted = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if model.page == .setup, model.setupStep == .access { model.setupStep = .shortcut }
            }
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
                    Text("Press it now to try it.")
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
            LensButton(title: "Continue", prominent: true) { model.setupStep = .tryIt }
        }
    }
}

private struct TryStep: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store

    var body: some View {
        SetupLayout(
            symbol: "wand.and.stars",
            title: "Try it on a draft",
            detail: "Here’s a message that could use a hand. It’s already selected, so press \(store.shortcut.display)."
        ) {
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
        } footer: {
            SmallButton(title: "Back", symbol: "arrow.left") { model.setupStep = .shortcut }
                .padding(.leading, -6)
            Spacer(minLength: 0)
            SmallButton(title: "Skip") { model.skipSetup() }
            LensButton(title: "Clean it up", prominent: true) { model.tryOnSample() }
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
