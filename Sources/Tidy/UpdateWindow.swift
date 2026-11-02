import AppKit
import SwiftUI

/// The "A new version of Tidy is available" window, laid out like Sparkle's (XReader uses Sparkle;
/// Tidy keeps its own updater): the app icon, the release notes, the auto-install checkbox, and
/// Skip This Version / Remind Me Later / Install Update. It's a normal window, not the panel.
@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    static let shared = UpdateWindow()
    private var window: NSWindow?

    /// `activate: false` (automatic checks) brings the window to the front without taking focus
    /// from what you're typing in; a click on it still goes straight to its buttons.
    func show(_ release: Updater.Release, activate: Bool) {
        window?.close()
        let content = UpdatePrompt(release: release, updater: Updater.shared) { [weak self] in
            self?.window?.close()
        }
        let host = FirstMouseHostingView(rootView: content)
        host.setFrameSize(host.fittingSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Software Update"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.delegate = self
        window.center()
        self.window = window

        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Hand focus back to the app you were in (Tidy has no other windows to fall back to).
        if NSApp.isActive, Updater.shared.isBusy?() != true {
            DispatchQueue.main.async { NSApp.hide(nil) }
        }
        window = nil
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct UpdatePrompt: View {
    let release: Updater.Release
    @ObservedObject var updater: Updater
    let close: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("A new version of Tidy is available.")
                        .font(.system(size: 13, weight: .bold))
                    Text("Tidy \(release.version) is now available—you have \(updater.currentVersion). Would you like to download it now?")
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            if !release.notes.isEmpty {
                notes
            }
            Toggle("Automatically download and install updates in the future", isOn: $updater.autoInstall)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            footer
        }
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 18, trailing: 20))
        .frame(width: 540)
    }

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(release.notes.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(Self.inline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 16))
        }
        .frame(height: 210)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder private var footer: some View {
        switch updater.state {
        case .installing:
            HStack(spacing: 12) {
                ProgressView().progressViewStyle(.linear)
                Text("Downloading Tidy \(release.version)…").font(.system(size: 11))
            }
            .frame(height: 28)
        default:
            VStack(alignment: .leading, spacing: 8) {
                if case .failed(let message) = updater.state {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
                HStack(spacing: 10) {
                    Button("Skip This Version") {
                        updater.skip(release)
                        close()
                    }
                    Spacer()
                    Button("Remind Me Later") { close() }
                        .keyboardShortcut(.cancelAction)
                    Button("Install Update") { Task { await updater.install(release) } }
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
    }

    private static func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}
