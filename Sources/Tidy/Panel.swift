import AppKit
import Carbon
import SwiftUI

// MARK: - Window

/// A Spotlight-style panel: it takes keyboard focus without activating Tidy, so the app you
/// were writing in stays active and gets focus straight back when the panel closes.
/// Borderless so the glass surface can have its own 24 pt corners; the window shadow follows them.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    let store: Store
    let model: PanelModel
    var openSettings: (@MainActor (SettingsTab) -> Void)?

    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    init(store: Store) {
        self.store = store
        self.model = PanelModel(store: store)
        model.onClose = { [weak self] in self?.close() }
        model.onCopy = { [weak self] text in self?.copy(text) }
        model.onReplace = { [weak self] text in self?.replace(text) }
        model.onAllSettings = { [weak self] in self?.openSettingsClosingPanel(.general) }
        model.onHeight = { [weak self] height in self?.fit(height: height) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(text: String, source: NSRunningApplication?, hadSelection: Bool, notice: String?) {
        model.reset(original: text, source: source, hadSelection: hadSelection)
        let panel = self.panel ?? makePanel()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        if let notice {
            model.error = notice
        } else if !text.trimmed.isEmpty {
            model.run()
        }
    }

    func close() {
        model.cancelRun()
        model.holdingOriginal = false
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    /// Settings is a normal window, so close the floating panel first or it would sit on top.
    private func openSettingsClosingPanel(_ tab: SettingsTab) {
        close()
        openSettings?(tab)
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        close()
    }

    private func replace(_ text: String) {
        guard let app = model.sourceApp, !app.isTerminated else {
            copy(text)
            return
        }
        close()
        let restore = store.restoreClipboard
        Task { @MainActor in
            if NSWorkspace.shared.frontmostApplication != app {
                let ok = app.activate(options: [])
                NSLog("Tidy: \(app.bundleIdentifier ?? "source") wasn't frontmost, activate returned \(ok)")
            }
            for _ in 0..<20 where NSWorkspace.shared.frontmostApplication != app {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            let front = NSWorkspace.shared.frontmostApplication
            NSLog("Tidy: pasting into \(front?.bundleIdentifier ?? "nil"), expected \(app.bundleIdentifier ?? "nil")")
            try? await Task.sleep(nanoseconds: 90_000_000)
            await Selection.paste(text, restoreClipboard: restore)
        }
    }

    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = false // the title bar is the drag handle
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        let host = NSHostingView(rootView: PanelView(model: model, store: store))
        host.sizingOptions = [] // the panel sizes itself to the content in fit(height:)
        p.contentView = host
        panel = p
        return p
    }

    /// Opens with the top edge a little above the middle of the screen with the mouse.
    /// The panel then grows downward as text arrives (see fit).
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        model.maxTextHeight = max(PanelView.minTextHeight, frame.height * 0.9 - PanelView.chromeHeight)
        let height = panel.frame.height
        let top = min(frame.maxY - 20, frame.midY + 280 + frame.height * 0.06)
        panel.setFrame(
            NSRect(x: frame.midX - PanelView.width / 2, y: top - height, width: PanelView.width, height: height),
            display: false
        )
    }

    /// Matches the window to the content's height, keeping the top edge where it is.
    private func fit(height: CGFloat) {
        guard let panel, height > 0, abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        if let visible = panel.screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                self?.handleKey(event) ?? false
            }
            return handled ? nil : event
        }
        // A global monitor only sees clicks that go to other apps, so any click it reports is
        // outside the panel: close, like Spotlight.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.isVisible == true { self?.close() }
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()

        if event.keyCode == UInt16(kVK_Escape) {
            // Esc steps back: history entry → history list → text → closed.
            if model.historySelection != nil {
                model.historySelection = nil
            } else if model.page != .editor {
                model.page = .editor
            } else {
                close()
            }
            return true
        }
        guard flags.contains(.command) else { return false }
        if model.page != .editor {
            // On History and Settings only editing shortcuts apply.
            let editing: Set<String> = ["c", "v", "x", "a", "z"]
            guard flags == .command || flags == [.command, .shift], editing.contains(key) || key == "," || key == "w" else {
                return true
            }
        }

        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            model.commit(.replace)
            return true
        }
        if flags == [.command, .shift] {
            switch key {
            case "c": model.commit(.copy); return true
            case "z": return NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            default: return false
            }
        }
        guard flags == .command else { return false }

        switch key {
        case "r": model.run(); return true
        case "d": model.toggleView(); return true
        case "w": close(); return true
        case ",": openSettingsClosingPanel(.general); return true
        case "v":
            let shouldAutoRun = model.original.trimmed.isEmpty && model.result.isEmpty && !model.isStreaming
            let pasted = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            if shouldAutoRun {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    self.model.runAfterPaste()
                }
            }
            return pasted
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        case "z": return NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        default:
            if let n = Int(key), (1...9).contains(n) {
                model.selectMode(index: n - 1)
                return true
            }
            return false
        }
    }
}

// MARK: - Model

@MainActor
final class PanelModel: ObservableObject {
    enum ResultView: Hashable { case changes, final }
    enum CommitAction { case replace, copy }
    enum Page: Hashable { case editor, history, settings }

    @Published var original = ""
    @Published var result = ""
    @Published var isStreaming = false
    @Published var error: String?
    @Published var modeID: UUID?
    @Published var tweak = ""
    @Published var view: ResultView = .final
    @Published var holdingOriginal = false
    @Published var page: Page = .editor {
        didSet {
            holdingOriginal = false
            if page != .history { historySelection = nil }
        }
    }
    @Published var historySelection: UUID?
    @Published var maxTextHeight: CGFloat = 480
    @Published var openToken = UUID()

    private(set) var suggestion = ""
    private(set) var sourceApp: NSRunningApplication?
    private(set) var hadSelection = false
    private var task: Task<Void, Never>?
    let store: Store

    var onClose: (@MainActor () -> Void)?
    var onCopy: (@MainActor (String) -> Void)?
    var onReplace: (@MainActor (String) -> Void)?
    var onAllSettings: (@MainActor () -> Void)?
    var onHeight: (@MainActor (CGFloat) -> Void)?

    init(store: Store) { self.store = store }

    var currentMode: Mode? { store.modes.first { $0.id == modeID } ?? store.modes.first }
    var sourceName: String? { sourceApp?.localizedName }
    var hasResult: Bool { !result.isEmpty }
    var canCommit: Bool { !isStreaming && !result.trimmed.isEmpty }

    var replaceTitle: String {
        if hadSelection { return sourceName.map { "Replace in \($0)" } ?? "Replace" }
        if let name = sourceName { return "Paste into \(name)" }
        return "Copy"
    }

    /// The compact status line under the command bar.
    var status: (text: String, isError: Bool)? {
        if let error { return (error, true) }
        if isStreaming { return ("Refining your words…", false) }
        guard hasResult else { return nil }
        if result.trimmed == original.trimmed { return ("Looks good already", false) }
        if hadSelection { return ("Ready to replace", false) }
        return (sourceName == nil ? "Ready to copy" : "Ready to paste", false)
    }

    var wordCount: Int { hasResult ? result.wordCount : original.wordCount }

    func reset(original text: String, source: NSRunningApplication?, hadSelection: Bool) {
        cancelRun()
        original = text
        result = ""
        suggestion = ""
        error = nil
        tweak = ""
        view = .final
        holdingOriginal = false
        page = .editor
        sourceApp = source
        self.hadSelection = hadSelection
        modeID = store.modes.first?.id
        openToken = UUID()
    }

    func selectMode(index: Int) {
        guard store.modes.indices.contains(index) else { return }
        modeID = store.modes[index].id
        run()
    }

    func run() {
        guard let mode = currentMode else { return }
        start(base: original, instruction: mode.instruction)
    }

    func runAfterPaste() {
        if !original.trimmed.isEmpty && result.isEmpty && !isStreaming { run() }
    }

    func runTweak() {
        let change = tweak.trimmed
        guard !change.isEmpty else { return }
        let base = result.trimmed.isEmpty ? original : result
        tweak = ""
        start(base: base, instruction: Prompts.tweakInstruction(change))
    }

    /// The title-bar icons: open a page, or go back to the text if it's already open.
    func togglePage(_ target: Page) {
        page = (page == target) ? .editor : target
    }

    func toggleView() {
        guard !isStreaming, hasResult else { return }
        view = (view == .changes) ? .final : .changes
    }

    func cancelRun() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    func commit(_ action: CommitAction) {
        guard canCommit else { return }
        let text = result
        store.addHistory(
            original: original, suggestion: suggestion, sent: text,
            app: sourceName, mode: currentMode?.name ?? ""
        )
        if action == .replace && sourceApp != nil {
            onReplace?(text)
        } else {
            onCopy?(text)
        }
    }

    private func start(base: String, instruction: String) {
        guard !base.trimmed.isEmpty else { return }
        guard let key = store.apiKey else {
            error = "Add your Anthropic API key in Settings (⌘,)."
            return
        }
        cancelRun()
        error = nil
        result = ""
        view = .final
        isStreaming = true

        let system = Prompts.system(voice: store.useVoice ? store.voiceProfile : nil)
        let user = Prompts.user(text: base, instruction: instruction, app: sourceName)
        let model = store.model

        task = Task { [weak self] in
            var text = ""
            do {
                for try await chunk in Claude.stream(apiKey: key, model: model, system: system, user: user) {
                    text += chunk
                    self?.result = Prompts.clean(text, streaming: true)
                }
                guard let self, !Task.isCancelled else { return }
                let finished = Prompts.clean(text, streaming: false)
                self.suggestion = finished
                self.result = finished
                self.isStreaming = false
                if finished.isEmpty { self.error = "Claude returned an empty response. Press ⌘R to try again." }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isStreaming = false
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - View (Lens)

struct PanelView: View {
    static let width: CGFloat = 602
    static let minTextHeight: CGFloat = 215
    /// Everything except the text area, used to cap the text so the panel fits on screen.
    static let chromeHeight: CGFloat = 320
    /// Width minus the 1 pt border and 33 pt padding on each side.
    static let textWidth: CGFloat = width - 68

    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @FocusState private var focus: Field?
    @State private var textHeight: CGFloat = PanelView.minTextHeight
    @State private var originalHeight: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum Field: Hashable { case tweak, compare }

    init(model: PanelModel, store: Store) {
        self.model = model
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            switch model.page {
            case .editor:
                editorHeader
                content
                modes
                VStack(spacing: 0) {
                    command
                    subfooter
                }
                .background(Color(Theme.soft))
            case .history:
                HistoryPage(model: model, store: store, maxHeight: pageMaxHeight)
            case .settings:
                SettingsPage(model: model, store: store, maxHeight: pageMaxHeight)
            }
        }
        .padding(1) // the surface's 1 pt border sits inside it, as in CSS
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { height in
            MainActor.assumeIsolated { model.onHeight?(height) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Glass(reduceTransparency: reduceTransparency))
        .clipShape(RoundedRectangle(cornerRadius: Glass.radius))
        .foregroundStyle(Color(Theme.ink))
        .font(.system(size: 13))
    }

    // Title bar: wordmark, source app, history, settings. Doubles as the drag handle.

    private var titlebar: some View {
        HStack(spacing: 14) {
            Wordmark()
            if let name = model.sourceName {
                HStack(spacing: 6) {
                    Image(systemName: Self.symbol(for: model.sourceApp?.bundleIdentifier))
                        .font(.system(size: 12))
                    Text(name).font(.system(size: 12)).lineBox(12)
                }
                .foregroundStyle(Color(Theme.muted))
                .padding(.leading, 17)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(Theme.rule)).frame(width: 1, height: 18)
                }
                .padding(.leading, 4)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "clock.arrow.circlepath", label: "History", active: model.page == .history) {
                model.togglePage(.history)
            }
            IconButton(symbol: "slider.horizontal.3", label: "Settings", active: model.page == .settings) {
                model.togglePage(.settings)
            }
            IconButton(symbol: "xmark", label: "Close  esc", size: 13) { model.onClose?() }
                .accessibilityLabel("Close")
        }
        .padding(.top, 21)
        .padding(.horizontal, 25)
        .padding(.bottom, 14)
        .background(WindowDragArea())
    }

    /// Pages get the room the editor's text and controls would have used.
    private var pageMaxHeight: CGFloat { model.maxTextHeight + Self.chromeHeight - 70 }

    // Final / Changes, and hold-to-see-original

    private var editorHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 15) {
                ViewTab(title: "Final", selected: model.view == .final) { model.view = .final }
                ViewTab(title: "Changes", selected: model.view == .changes) { model.view = .changes }
            }
            .disabled(!model.hasResult || model.isStreaming)
            Spacer(minLength: 0)
            holdControl
        }
        .padding(.top, 12)
        .padding(.horizontal, 31)
    }

    private var holdControl: some View {
        let enabled = model.hasResult && !model.original.trimmed.isEmpty
        let holding = model.holdingOriginal
        return HoldButton(holding: holding) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder").font(.system(size: 12))
                Text("Hold for original").font(.system(size: 11)).lineBox(11)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !model.holdingOriginal { model.holdingOriginal = true } }
                .onEnded { _ in model.holdingOriginal = false }
        )
        .focusable(enabled)
        .focused($focus, equals: .compare)
        .onKeyPress(keys: [.space, .return], phases: [.down, .repeat, .up]) { press in
            model.holdingOriginal = press.phase != .up
            return .handled
        }
        .onChange(of: focus) { if focus != .compare { model.holdingOriginal = false } }
        .help("Hold to see your original")
        .accessibilityLabel("Hold to see original")
        .accessibilityAddTraits(.isButton)
        .opacity(enabled ? 1 : 0.5)
        .allowsHitTesting(enabled)
    }

    // The text: your draft before a result exists, then the result (streaming, Final or Changes).

    private var content: some View {
        let height = min(max(textHeight, Self.minTextHeight), model.maxTextHeight)
        return Group {
            if model.holdingOriginal {
                // Never shorter than the result it covers, so the controls below don't jump.
                let label: CGFloat = 16.5 + 12
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your original")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Theme.accent))
                        .lineBox(11)
                    ProseView(content: .styled(Styled.prose(model.original)), height: $originalHeight)
                        .frame(height: min(max(height - label, originalHeight), model.maxTextHeight - label))
                }
            } else if !model.hasResult && !model.isStreaming {
                ProseView(
                    content: .editable($model.original),
                    focusToken: model.original.trimmed.isEmpty ? model.openToken : nil,
                    height: $textHeight
                )
                .overlay(alignment: .topLeading) {
                    if model.original.isEmpty {
                        Text("Paste a message (⌘V) and it cleans up right away.")
                            .font(.system(size: Theme.prose.size))
                            .tracking(Theme.prose.kern)
                            .lineSpacing(Theme.prose.size * (Theme.prose.lineHeight - 1.2))
                            .foregroundStyle(Color(Theme.muted))
                            .padding(.top, 3)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: height)
                .accessibilityLabel("Your draft")
            } else if model.isStreaming {
                ProseView(content: .styled(Styled.prose(model.result)), followTail: true, height: $textHeight)
                    .frame(height: height)
                    .accessibilityLabel("Cleaned-up text, writing")
            } else if model.view == .final {
                ProseView(content: .editable($model.result), height: $textHeight)
                    .frame(height: height)
                    .accessibilityLabel("Edit final text")
            } else {
                ProseView(content: .styled(Styled.diff(from: model.original, to: model.result)), height: $textHeight)
                    .frame(height: height)
                    .accessibilityLabel("Changes")
            }
        }
        .padding(EdgeInsets(top: 25, leading: 33, bottom: 18, trailing: 33))
    }

    // Writing modes

    private var modes: some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(store.modes.enumerated()), id: \.element.id) { index, mode in
                ModeButton(
                    title: mode.name,
                    shortcut: index < 9 ? "⌘\(index + 1)" : nil,
                    selected: mode.id == model.currentMode?.id
                ) {
                    model.selectMode(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 7)
        .padding(.horizontal, 23)
        .padding(.bottom, 13) // 12 + the 1 pt rule
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(Theme.rule)).frame(height: 1)
        }
    }

    // Refinement field and the replace action

    private var command: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(Theme.accent))
                    .accessibilityHidden(true)
                TextField(
                    "Refine your text", text: $model.tweak,
                    prompt: Text("A little warmer? Mention Friday?").foregroundColor(Color(Theme.muted))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineBox(13)
                .padding(.vertical, 6)
                .focused($focus, equals: .tweak)
                .onSubmit { model.runTweak() }
                IconButton(symbol: "arrow.up", label: "Apply refinement") { model.runTweak() }
            }
            .disabled(model.isStreaming || (model.result.isEmpty && model.original.trimmed.isEmpty))
            PrimaryButton(title: model.replaceTitle) { model.commit(.replace) }
                .disabled(!model.canCommit)
        }
        .padding(.vertical, 17)
        .padding(.horizontal, 25)
    }

    private var subfooter: some View {
        HStack(spacing: 10) {
            if let status = model.status {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(status.isError ? Theme.red : Theme.green))
                        .frame(width: 4, height: 4)
                    Text(status.text)
                        .foregroundStyle(status.isError ? Color(Theme.red) : Color(Theme.muted))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineBox(11)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            if model.wordCount > 0 {
                Text(model.wordCount == 1 ? "1 word" : "\(model.wordCount) words").lineBox(11)
            }
            IconButton(symbol: "arrow.counterclockwise", label: "Try again", size: 12, box: CGSize(width: 20, height: 18)) { model.run() }
                .disabled(model.original.trimmed.isEmpty || model.isStreaming)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(Theme.muted))
        .padding(.horizontal, 27)
        .padding(.bottom, 15)
    }

    static func symbol(for bundleID: String?) -> String {
        switch bundleID {
        case "com.apple.mail": "envelope"
        case "com.apple.MobileSMS": "message"
        case "com.apple.Notes": "note.text"
        case "com.tinyspeck.slackmacgap": "number"
        case "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox": "globe"
        default: "macwindow"
        }
    }
}

/// No system dimming or press effect; each control draws its own states (disabled = 50% opacity).
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

extension View {
    /// The design's base line-height (1.5): text sits in a line box 1.5× its size, as in CSS.
    func lineBox(_ size: CGFloat) -> some View { frame(minHeight: size * 1.5) }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Small components

/// A 32 pt icon button with the quiet hover fill used across the panel.
struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 14
    var box = CGSize(width: 32, height: 32)
    var active = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: box.width, height: box.height)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill((hovering && isEnabled) || active ? Color(Theme.layer) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct ViewTab: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .lineBox(12)
                .padding(.vertical, 5)
                .padding(.bottom, 1) // room for the underline, like a CSS border
                .foregroundStyle(Color(selected || (hovering && isEnabled) ? Theme.ink : Theme.muted))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(selected ? Color(Theme.ink) : .clear).frame(height: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HoldButton<Label: View>: View {
    let holding: Bool
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        label
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .foregroundStyle(Color(holding ? Theme.accent : Theme.muted))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(holding ? Color(Theme.accentSoft) : hovering ? Color(Theme.layer) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct ModeButton: View {
    let title: String
    let shortcut: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                if selected, let shortcut {
                    Text(shortcut).font(.system(size: 11)).opacity(0.6)
                }
            }
            .font(.system(size: 12))
            .lineBox(12)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .foregroundStyle(Color(selected ? Theme.accent : Theme.muted))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color(Theme.accentSoft) : hovering ? Color(Theme.layer) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .onHover { hovering = $0 }
        .help(shortcut.map { "\(title)  \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Dark neutral in light mode, pale neutral in dark mode, with the ⌘↩ hint after a hairline.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Text(title)
                    .font(Font(NSFont.systemFont(ofSize: 12, weight: Theme.actionWeight) as CTFont))
                    .lineLimit(1)
                    .lineBox(12)
                HStack(spacing: 2) {
                    Text("⌘").font(.system(size: 11)).opacity(0.6)
                    Image(systemName: "arrow.turn.down.left").font(.system(size: 13))
                }
                .opacity(0.7)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(Theme.onAction).opacity(0.2)).frame(width: 1)
                }
                .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 12))
            .foregroundStyle(Color(Theme.onAction))
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(Theme.action))
                    .brightness(hovering && isEnabled ? 0.04 : 0)
                    .shadow(color: Color(Theme.shadow), radius: 2.5, y: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BareButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help("⌘↩")
    }
}

/// Wraps the mode buttons onto more lines when there are many custom modes.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

/// The frosted surface: a behind-window blur under 87% paper, a faint diagonal reflection,
/// a fine rim and a top-edge highlight. Opaque when Reduce Transparency is on.
struct Glass: View {
    static let radius: CGFloat = 24
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius)
        ZStack {
            if reduceTransparency {
                shape.fill(Color(Theme.opaque))
            } else {
                VisualEffect(cornerRadius: Self.radius)
                shape.fill(Color(Theme.glass))
                shape.fill(LinearGradient(
                    stops: [.init(color: Color(Theme.reflection), location: 0), .init(color: .clear, location: 0.48)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            }
            RoundedRectangle(cornerRadius: Self.radius - 1)
                .strokeBorder(Color(Theme.innerRim), lineWidth: 1)
                .padding(1)
            RoundedRectangle(cornerRadius: Self.radius - 1)
                .strokeBorder(
                    LinearGradient(colors: [Color(Theme.topHighlight), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.04)),
                    lineWidth: 1
                )
                .padding(1)
            shape.strokeBorder(Color(Theme.rim), lineWidth: 1)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    /// A stretchable rounded-rect mask, so the blur itself has rounded corners.
    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Lets the borderless panel be dragged from its title bar.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// The panel's text: an NSTextView (TextKit 1) so the type matches the design exactly
/// (line height, tracking, rounded diff highlights). Reports its content height so the
/// panel can fit the text instead of clipping it.
struct ProseView: NSViewRepresentable {
    enum Content {
        case editable(Binding<String>)
        case styled(NSAttributedString)
    }

    let content: Content
    var followTail = false
    /// Focuses the text view whenever this changes (editable text only).
    var focusToken: UUID?
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = NSTextView(usingTextLayoutManager: false)
        textView.textContainer?.replaceLayoutManager(HighlightLayoutManager())
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: PanelView.textWidth, height: .greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.frame = NSRect(x: 0, y: 0, width: PanelView.textWidth, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.insertionPointColor = Theme.ink
        textView.typingAttributes = Theme.prose.attributes()
        textView.delegate = context.coordinator
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        let coordinator = context.coordinator
        coordinator.parent = self

        switch content {
        case .editable(let text):
            textView.isEditable = true
            textView.isSelectable = true
            if textView.string != text.wrappedValue {
                let selection = textView.selectedRanges
                storage.setAttributedString(Styled.prose(text.wrappedValue))
                if (selection.last as? NSRange).map({ NSMaxRange($0) <= storage.length }) == true {
                    textView.selectedRanges = selection
                }
            }
            if let token = focusToken, token != coordinator.focusedToken {
                coordinator.focusedToken = token
                DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
            }
        case .styled(let attributed):
            textView.isEditable = false
            textView.isSelectable = true
            if !storage.isEqual(to: attributed) {
                storage.setAttributedString(attributed)
                if followTail { textView.scrollToEndOfDocument(nil) }
            }
        }
        coordinator.reportHeight(of: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ProseView?
        var focusedToken: UUID?

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  case .editable(let text) = parent?.content else { return }
            text.wrappedValue = textView.string
            reportHeight(of: textView)
        }

        /// Tab moves focus (to the refine field) instead of typing a tab into the message.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }

        func reportHeight(of textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let height = ceil(layout.usedRect(for: container).height)
            DispatchQueue.main.async { [weak self] in
                guard let parent = self?.parent, abs(parent.height - height) > 0.5 else { return }
                parent.height = height
            }
        }
    }
}

/// Draws background highlights (the diff washes, the selection) as rounded boxes the height
/// of the text rather than the full, airy line, like an inline CSS background.
final class HighlightLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
        forCharacterRange charRange: NSRange, color: NSColor
    ) {
        guard let storage = textStorage, charRange.location < storage.length,
              let font = storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? NSFont else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        let height = ceil(font.ascender - font.descender) + 2
        color.setFill()
        for i in 0..<rectCount {
            var rect = rectArray[i]
            guard rect.height > height else {
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
                continue
            }
            rect.origin.y += (rect.height - height) / 2
            rect.size.height = height
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
    }
}
