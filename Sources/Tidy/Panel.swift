import AppKit
import Carbon
import SwiftUI

// MARK: - Window

/// A Spotlight-style panel: it takes keyboard focus without activating Tidy, so the app you
/// were writing in stays active and gets focus straight back when the panel closes.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    let store: Store
    let model: PanelModel
    var openSettings: (@MainActor () -> Void)?

    private var panel: FloatingPanel?
    private var keyMonitor: Any?

    init(store: Store) {
        self.store = store
        self.model = PanelModel(store: store)
        model.onClose = { [weak self] in self?.close() }
        model.onCopy = { [weak self] text in self?.copy(text) }
        model.onReplace = { [weak self] text in self?.replace(text) }
        model.onSettings = { [weak self] in self?.openSettings?() }
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
        removeKeyMonitor()
        panel?.orderOut(nil)
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 590),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 560, height: 460)
        p.isOpaque = false
        p.backgroundColor = .clear
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            p.standardWindowButton(button)?.isHidden = true
        }
        p.contentView = NSHostingView(rootView: PanelView(model: model, store: store))
        panel = p
        return p
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + frame.height * 0.06
        )
        panel.setFrameOrigin(origin)
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
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()

        if event.keyCode == UInt16(kVK_Escape) {
            close()
            return true
        }
        guard flags.contains(.command) else { return false }

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
        case ",": openSettings?(); return true
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

    @Published var original = ""
    @Published var result = ""
    @Published var isStreaming = false
    @Published var error: String?
    @Published var modeID: UUID?
    @Published var tweak = ""
    @Published var view: ResultView = .changes
    @Published var elapsed: Double?
    @Published var openToken = UUID()

    private(set) var suggestion = ""
    private(set) var sourceApp: NSRunningApplication?
    private(set) var hadSelection = false
    private var task: Task<Void, Never>?
    let store: Store

    var onClose: (@MainActor () -> Void)?
    var onCopy: (@MainActor (String) -> Void)?
    var onReplace: (@MainActor (String) -> Void)?
    var onSettings: (@MainActor () -> Void)?

    init(store: Store) { self.store = store }

    var currentMode: Mode? { store.modes.first { $0.id == modeID } ?? store.modes.first }
    var sourceName: String? { sourceApp?.localizedName }
    var canCommit: Bool { !isStreaming && !result.trimmed.isEmpty }

    var replaceTitle: String {
        if hadSelection { return "Replace" }
        if let name = sourceName { return "Paste into \(name)" }
        return "Copy"
    }

    var summary: String {
        guard let elapsed else { return "" }
        let time = String(format: "%.1fs", elapsed)
        if result.trimmed == original.trimmed { return "Looks good already · \(time)" }
        var s = "\(original.wordCount) → \(result.wordCount) words · \(time)"
        if !suggestion.isEmpty && result.trimmed != suggestion.trimmed { s += " · edited by you" }
        return s
    }

    func reset(original text: String, source: NSRunningApplication?, hadSelection: Bool) {
        cancelRun()
        original = text
        result = ""
        suggestion = ""
        error = nil
        tweak = ""
        elapsed = nil
        view = .changes
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

    func toggleView() {
        guard !isStreaming else { return }
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
        view = .changes
        elapsed = nil
        isStreaming = true

        let system = Prompts.system(voice: store.useVoice ? store.voiceProfile : nil)
        let user = Prompts.user(text: base, instruction: instruction, app: sourceName)
        let model = store.model
        let started = Date()

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
                self.elapsed = Date().timeIntervalSince(started)
                if finished.isEmpty { self.error = "Claude returned an empty response. Press ⌘R to try again." }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isStreaming = false
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - View

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @FocusState private var focus: Field?

    enum Field: Hashable { case original, result, tweak }

    init(model: PanelModel, store: Store) {
        self.model = model
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            draft
            output
            tweakField
            footer
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(minWidth: 560, minHeight: 440)
        .background(VisualEffect().ignoresSafeArea())
        .onAppear(perform: focusForOpen)
        .onChange(of: model.openToken) { focusForOpen() }
    }

    private func focusForOpen() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            focus = model.original.trimmed.isEmpty ? .original : nil
        }
    }

    // Header: modes, model, settings

    private var header: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(store.modes.enumerated()), id: \.element.id) { index, mode in
                        ModeChip(
                            title: mode.name,
                            selected: mode.id == model.currentMode?.id,
                            help: index < 9 ? "\(mode.name)  ⌘\(index + 1)" : mode.name
                        ) {
                            model.selectMode(index: index)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 8)
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
                Text(Claude.shortName(store.model))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Model")

            Button {
                model.onSettings?()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings  ⌘,")
        }
    }

    // Your draft

    private var draft: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: model.sourceName.map { "Your draft · \($0)" } ?? "Your draft")
                Spacer()
                Button(model.result.isEmpty && !model.isStreaming ? "Clean up  ⌘R" : "Run again  ⌘R") {
                    model.run()
                }
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
                .disabled(model.original.trimmed.isEmpty)
            }
            TextEditor(text: $model.original)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
                .focused($focus, equals: .original)
                .frame(height: 92)
                .card()
        }
    }

    // Cleaned-up output

    private var output: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SectionLabel(text: "Cleaned up")
                if model.isStreaming { ProgressView().controlSize(.mini) }
                Spacer()
                Picker("", selection: $model.view) {
                    Text("Changes").tag(PanelModel.ResultView.changes)
                    Text("Final").tag(PanelModel.ResultView.final)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(model.isStreaming || model.result.isEmpty)
                .help("⌘D switches. Edit the text in Final before sending.")
            }
            ZStack {
                if model.isStreaming || model.view == .changes {
                    RichText(
                        text: model.isStreaming
                            ? Styled.plain(model.result)
                            : Styled.diff(from: model.original, to: model.result),
                        followTail: model.isStreaming
                    )
                } else {
                    TextEditor(text: $model.result)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 10)
                        .focused($focus, equals: .result)
                }

                if model.isStreaming && model.result.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning up with \(Claude.shortName(store.model))…")
                            .foregroundStyle(.secondary)
                    }
                } else if !model.isStreaming && model.result.isEmpty && model.error == nil && model.original.trimmed.isEmpty {
                    Text("Paste a message above (⌘V) and it cleans up right away.")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
        }
        .frame(maxHeight: .infinity)
    }

    private var tweakField: some View {
        TextField("Tweak it: “warmer close”, “mention Friday”, “drop the last line”…  then ↩", text: $model.tweak)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .focused($focus, equals: .tweak)
            .onSubmit { model.runTweak() }
            .disabled(model.isStreaming || (model.result.isEmpty && model.original.trimmed.isEmpty))
            .card()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            status.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.onClose?()
            } label: {
                KeyLabel(title: "Cancel", keys: "esc")
            }
            Button {
                model.commit(.copy)
            } label: {
                KeyLabel(title: "Copy", keys: "⌘⇧C")
            }
            .disabled(!model.canCommit)
            Button {
                model.commit(.replace)
            } label: {
                KeyLabel(title: model.replaceTitle, keys: "⌘↩")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canCommit)
        }
        .controlSize(.large)
    }

    @ViewBuilder private var status: some View {
        if let error = model.error {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(Color.red)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.isStreaming {
            Text("Writing…").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Text(model.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

// MARK: - Small components

struct ModeChip: View {
    let title: String
    let selected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct KeyLabel: View {
    let title: String
    let keys: String
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Text(keys).font(.system(size: 11)).opacity(0.6)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Read-only, selectable rich text (used for streaming output and the change highlights).
struct RichText: NSViewRepresentable {
    let text: NSAttributedString
    var followTail = false

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.isRichText = true
            textView.textContainerInset = NSSize(width: 7, height: 10)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        if !storage.isEqual(to: text) {
            storage.setAttributedString(text)
            if followTail { textView.scrollToEndOfDocument(nil) }
        }
    }
}

extension View {
    func card() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }
}
