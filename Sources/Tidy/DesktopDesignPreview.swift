#if DEBUG
import AppKit
import TidyCore

/// A separate bundle launches this path; it never constructs Store.shared or AppDelegate.
/// Settings/files are temporary, Keychain access is injected out, and the stream is recorded.
@MainActor enum DesktopDesignPreview {
    static func run() {
        let app = NSApplication.shared
        let host = PreviewHost()
        app.delegate = host
        app.setActivationPolicy(.regular)
        withExtendedLifetime(host) { app.run() }
    }
}

@MainActor private final class PreviewHost: NSObject, NSApplicationDelegate {
    let controller: PanelController
    let domain: String
    let folder: URL
    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        domain = "TidyDesignPreview.\(UUID())"
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        let store = Store(defaults: UserDefaults(suiteName: domain)!, folder: folder,
                          readKey: { arguments.contains("--disconnected") ? nil : "recorded-preview-placeholder" },
                          writeKey: { _ in }, checkKey: { _ in .valid },
                          accessibilityAllowed: { true }, registersHotKey: false, isDesignPreview: true)
        controller = PanelController(store: store, transport: { _, _, _, _ in
            AsyncThrowingStream { stream in
                stream.yield("Hey, can you look over the deck before tomorrow? Slide 4 is confusing, and the numbers on slide 7 don’t match the Q3 report.")
                stream.finish()
            }
        })
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let menu = NSMenu(); appItem.submenu = menu
        for (title, selector, key) in [
            ("Settings", #selector(settings), ","),
            ("Setup walkthrough", #selector(setup), ""),
            ("Recorded sample", #selector(sample), ""),
            ("Toggle appearance", #selector(appearance), ""),
            ("Quit preview", #selector(quit), "q")
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self; menu.addItem(item)
        }
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        NSApp.mainMenu = main
        if ProcessInfo.processInfo.arguments.contains("--setup") { setup() } else { settings() }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: folder)
    }
    @objc private func settings() { controller.showSettings(.general) }
    @objc private func setup() { controller.showSetup() }
    @objc private func sample() { controller.showSettings(.general); controller.model.tryOnSample() }
    @objc private func appearance() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSApp.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
#endif
