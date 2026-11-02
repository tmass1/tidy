import SwiftUI
import TidyCore

struct EditorView: View {
    enum Review: String, CaseIterable { case original = "Original", changes = "Changes", final = "Final" }
    @ObservedObject var store: MobileStore
    @StateObject private var session: RewriteSession
    @State private var modeID: UUID?
    @State private var review = Review.final
    @State private var tweak = ""
    @State private var settings = false
    @State private var share: SharePayload?
    @State private var copied = false
    @FocusState private var editing: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var proseSize = 23
    let isExtension: Bool
    let onClose: (() -> Void)?

    init(store: MobileStore, text: String = "", isExtension: Bool = false, onClose: (() -> Void)? = nil) {
        self.store = store; self.isExtension = isExtension; self.onClose = onClose
        let session = RewriteSession { [weak store] request in
            guard let store else { return AsyncThrowingStream { $0.finish() } }
            return store.stream(request)
        }
        session.original = text
        _session = StateObject(wrappedValue: session)
        _modeID = State(initialValue: store.modes.first?.id)
    }
    private var mode: Mode? { store.modes.first { $0.id == modeID } ?? store.modes.first }
    private var busy: Bool { session.phase == .streaming }
    private var ready: Bool { session.phase == .ready && !session.result.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.isPreview {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Sample preview", systemImage: "play.circle")
                                .font(.headline).accessibilityIdentifier("previewNotice")
                            Text("A recorded rewrite. No API request.").font(.subheadline)
                            Button("Exit sample") { store.exitPreview() }
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).foregroundStyle(Lens.accent)
                            .background(Lens.accentSoft, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if session.phase != .idle {
                        Picker("Review", selection: $review) {
                            ForEach(Review.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("reviewPicker")
                    }
                    prose
                    modePicker
                    if ready {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "arrow.turn.down.right").foregroundStyle(Lens.accent).padding(.top, 13)
                            TextField("Change anything…", text: $tweak, axis: .vertical)
                                .padding(.vertical, 12).focused($editing)
                                .accessibilityHint("For example, warmer close or mention Friday")
                            Button { rewrite(tweak: true) } label: {
                                Image(systemName: "arrow.up").frame(width: 44, height: 44)
                            }.accessibilityLabel("Apply change").disabled(tweak.trimmed.isEmpty)
                        }
                        .padding(.horizontal, 12).background(Lens.well, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let error = session.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Lens.red).font(.subheadline).accessibilityIdentifier("rewriteError")
                    }
                    if let storageError = store.storageError {
                        Text(storageError).font(.footnote).foregroundStyle(Lens.red)
                    }
                    if isExtension {
                        Text("Copy the result, then paste it into your message.")
                            .font(.footnote).foregroundStyle(Lens.muted)
                    }
                    #if DEBUG
                    if !isExtension && store.isPreview {
                        Button { share = SharePayload(text: SampleRewrite.original) } label: {
                            Label("Share sample to Tidy", systemImage: "square.and.arrow.up")
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("shareSample")
                        Text("The sample uses a recorded rewrite. Custom instructions and other modes need your API key.")
                            .font(.caption).foregroundStyle(Lens.muted)
                    }
                    #endif
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Lens.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("tidy").font(.system(size: 24, weight: .bold)).fixedSize().tracking(-1.2).foregroundStyle(Lens.ink)
                        .accessibilityLabel("Tidy")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isExtension {
                        Button { session.reset(); review = .final; copied = false; editing = true } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("Edit original")
                        Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings")
                    } else {
                        Button("Done") { session.cancel(); onClose?() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }
                }
            }
            .toolbarBackground(Lens.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $settings, onDismiss: {
                store.reload()
                if !store.modes.contains(where: { $0.id == modeID }) { modeID = store.modes.first?.id }
            }) { SettingsView(store: store) }
            .sheet(item: $share) { ShareSheet(text: $0.text) }
            .onChange(of: scenePhase) { _, phase in if phase == .background { session.cancel() } }
            .onChange(of: session.result) { _, _ in copied = false }
            .onChange(of: store.isPreview) { _, value in
                session.reset(); copied = false; review = .final
                #if DEBUG
                if !value && !isExtension && [SampleRewrite.original, SampleRewrite.final, SampleRewrite.shorter].contains(session.original.trimmed) {
                    session.original = ""
                }
                #endif
            }
            .onChange(of: session.phase) { _, phase in
                copied = false
                if phase == .ready { UIAccessibility.post(notification: .announcement, argument: "Rewrite ready") }
            }
            .onDisappear { session.cancel() }
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        }.tint(Lens.accent).foregroundStyle(Lens.ink)
    }

    @ViewBuilder private var prose: some View {
        if session.phase == .idle {
            VStack(alignment: .leading, spacing: 12) {
                Text(isExtension ? "SHARED TEXT" : "YOUR MESSAGE").font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(Lens.muted)
                ZStack(alignment: .topLeading) {
                    if session.original.isEmpty {
                        Text("A little clearer.\nStill you.").font(.system(size: proseSize)).foregroundStyle(Lens.muted)
                            .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                    }
                    TextEditor(text: $session.original).scrollContentBackground(.hidden)
                        .font(.system(size: proseSize)).lineSpacing(7).frame(minHeight: 270)
                        .focused($editing).accessibilityLabel("Your message").accessibilityIdentifier("originalEditor")
                }
                if session.original.isEmpty {
                    HStack(spacing: 20) {
                        PasteButton(payloadType: String.self) { strings in session.original = strings.joined(separator: "\n\n") }
                            .labelStyle(.titleAndIcon)
                        #if DEBUG
                        Button("Try a sample") {
                            store.isPreview = true; store.defaults.set(true, forKey: "previewTransport")
                            session.original = SampleRewrite.original
                        }.frame(minHeight: 44)
                        #endif
                    }
                    Text("Write here, paste a draft, or share text to Tidy from another app.")
                        .font(.subheadline).foregroundStyle(Lens.muted)
                }
            }
        } else if review == .original {
            Text(session.original).font(.system(size: proseSize)).lineSpacing(8).textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        } else if review == .changes {
            VStack(alignment: .leading, spacing: 18) {
                if busy { Text("Changes appear when the rewrite finishes.").foregroundStyle(Lens.muted) }
                else if ready {
                    if let changes = Lens.changes(original: session.original, result: session.result) {
                        HStack { Text("Removed").strikethrough().foregroundStyle(Lens.red); Text("Added").underline().foregroundStyle(Lens.green) }
                            .font(.caption).accessibilityLabel("Removed text is struck through. Added text is underlined.")
                        Text(changes).font(.body).lineSpacing(9).textSelection(.enabled).accessibilityIdentifier("changesText")
                    } else {
                        Text("Changes are unavailable for a message this long. Compare Original and Final instead.")
                            .foregroundStyle(Lens.muted)
                    }
                } else { Text("Finish a rewrite to review its changes.").foregroundStyle(Lens.muted) }
            }.frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        } else if session.phase == .ready {
            TextEditor(text: $session.result).scrollContentBackground(.hidden)
                .font(.system(size: proseSize)).lineSpacing(7).frame(minHeight: 300)
                .focused($editing).accessibilityLabel("Final message")
                .accessibilityIdentifier(isExtension ? "extensionFinalEditor" : "finalEditor")
        } else {
            Text(session.result.isEmpty ? session.original : session.result)
                .font(.system(size: proseSize)).lineSpacing(8)
                .foregroundStyle(session.result.isEmpty ? Lens.muted : Lens.ink)
                .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODE").font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(Lens.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.modes) { item in
                        Button {
                            modeID = item.id
                            if session.phase != .idle { rewrite() }
                        } label: {
                            Text(item.name).font(.subheadline.weight(item.id == mode?.id ? .semibold : .regular))
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .foregroundStyle(item.id == mode?.id ? Lens.accent : Lens.muted)
                                .background(item.id == mode?.id ? Lens.accentSoft : Lens.well.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityAddTraits(item.id == mode?.id ? .isSelected : [])
                    }
                }
            }
        }
    }
    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                if busy { ProgressView().controlSize(.small) }
                else { Circle().fill(ready ? Lens.green : Lens.muted).frame(width: 5, height: 5).accessibilityHidden(true) }
                Text(typeSize.isAccessibilitySize ? compactStatus : status)
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rewriteStatus")
                    .accessibilityValue("\((session.phase == .idle ? session.original : session.result).wordCount) words")
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Text("\((session.phase == .idle ? session.original : session.result).wordCount) words").font(.caption)
                }
            }.foregroundStyle(Lens.muted)
            if busy {
                Button(typeSize.isAccessibilitySize ? "Cancel" : "Cancel rewrite") { session.cancel() }.buttonStyle(LensPrimary())
            } else if session.phase == .ready {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = session.result
                        copied = true
                        UIAccessibility.post(notification: .announcement, argument: "Copied")
                    } label: {
                        if typeSize.isAccessibilitySize { Text(copied ? "Copied" : "Copy").contentTransition(.identity).fixedSize(horizontal: false, vertical: true) }
                        else { Label(copied ? "Copied" : "Copy result", systemImage: copied ? "checkmark" : "doc.on.doc").contentTransition(.identity) }
                    }
                        .buttonStyle(LensPrimary()).accessibilityIdentifier("copyResult")
                        .disabled(!ready).opacity(ready ? 1 : 0.45)
                    Button { share = SharePayload(text: session.result) } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 22)).frame(width: 54, height: 52)
                            .background(Lens.accentSoft, in: RoundedRectangle(cornerRadius: 16))
                    }.accessibilityLabel("Share result").disabled(!ready).opacity(ready ? 1 : 0.45)
                }
            } else if !store.hasKey && !store.isPreview && !isExtension {
                Button("Set up Tidy") { editing = false; settings = true }.buttonStyle(LensPrimary())
            } else {
                Button(session.phase == .failed || session.phase == .cancelled ? "Retry" : "Rewrite") {
                    editing = false; review = .final
                    if session.phase == .failed || session.phase == .cancelled { session.retry() }
                    else { rewrite() }
                }.buttonStyle(LensPrimary()).accessibilityIdentifier(isExtension ? "extensionRewrite" : "rewrite")
                    .disabled(session.original.trimmed.isEmpty || mode == nil)
                    .opacity(session.original.trimmed.isEmpty ? 0.45 : 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
        .animation(nil, value: copied)
        .background(Lens.paper.shadow(color: .black.opacity(0.04), radius: 12, y: -5))
    }
    private var compactStatus: String {
        switch session.phase {
        case .idle: return !store.hasKey && !store.isPreview ? "Add your API key" : "Ready"
        case .streaming: return "Rewriting…"
        case .ready: return !ready ? "Final is empty" : (copied ? "Copied" : "Ready to copy")
        case .cancelled: return "Cancelled"
        case .failed: return "Couldn’t finish"
        }
    }
    private var status: String {
        switch session.phase {
        case .idle:
            if !store.hasKey && !store.isPreview { return isExtension ? "Add your API key in the Tidy app" : "Connect your key to begin" }
            return session.original.trimmed.isEmpty ? "Paste or write a message" : "Ready to rewrite"
        case .streaming: return "Tidying your message…"
        case .ready: return !ready ? "Final is empty" : (copied ? "Copied · ready to paste" : "Ready to copy")
        case .cancelled: return "Cancelled · draft kept"
        case .failed: return "Couldn’t finish · try again"
        }
    }
    private func rewrite(tweak isTweak: Bool = false) {
        guard let mode else { return }
        editing = false; review = .final
        let text = isTweak ? session.result : session.original
        let instruction = isTweak ? Prompts.tweakInstruction(tweak.trimmed) : mode.instruction
        session.run(RewriteRequest(text: text, instruction: instruction, model: store.model,
                                   voice: store.useVoice ? store.voiceProfile : nil))
        if isTweak { tweak = "" }
    }
}
private struct SharePayload: Identifiable { let id = UUID(); let text: String }

#Preview("Tidy · iPhone") { EditorView(store: MobileStore()) }
