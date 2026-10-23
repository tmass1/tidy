import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var lastTrigger = Date.distantPast

    private lazy var panel: PanelController = {
        let controller = PanelController(store: store)
        controller.openSettings = { [weak self] tab in self?.showSettings(tab) }
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()

        HotKeyCenter.shared.action = { [weak self] in self?.trigger() }
        store.registerHotKey()

        if !store.hasAPIKey { showSettings(.general) }
        Updater.shared.startAutomaticChecks()
        _ = Selection.isTrusted(prompt: true) // asks for Accessibility on first launch
    }

    // MARK: Trigger

    func trigger() {
        guard Date().timeIntervalSince(lastTrigger) > 0.3 else { return }
        lastTrigger = Date()

        if panel.isVisible {
            panel.close()
            return
        }
        let source = Self.frontmostOtherApp()
        NSLog("Tidy: triggered from \(source?.bundleIdentifier ?? "nil")")
        guard Selection.isTrusted(prompt: false) else {
            NSLog("Tidy: not trusted for Accessibility")
            _ = Selection.isTrusted(prompt: true)
            panel.show(
                text: "", source: source, hadSelection: false,
                notice: "Turn on Tidy in System Settings › Privacy & Security › Accessibility so it can read your selection. You can paste text here meanwhile."
            )
            return
        }
        Task {
            let text = await Selection.copySelection()
            self.panel.show(text: text ?? "", source: source, hadSelection: text != nil, notice: nil)
        }
    }

    private static func frontmostOtherApp() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Tidy")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addItem(to: menu, "Clean Up Selection     \(store.shortcut.display)", #selector(menuCleanSelection))
        addItem(to: menu, "Clean Up Clipboard", #selector(menuCleanClipboard))
        menu.addItem(.separator())
        if let release = Updater.shared.available {
            addItem(to: menu, "Update to Tidy \(release.version)…", #selector(menuUpdates))
        } else {
            addItem(to: menu, "Check for Updates…", #selector(menuUpdates))
        }
        addItem(to: menu, "History…", #selector(menuHistory))
        addItem(to: menu, "Settings…", #selector(menuSettings), key: ",")
        menu.addItem(.separator())
        addItem(to: menu, "Quit Tidy", #selector(menuQuit), key: "q")
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func menuCleanSelection() {
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // let the menu close first
            self.trigger()
        }
    }

    @objc private func menuCleanClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        panel.show(text: text, source: Self.frontmostOtherApp(), hadSelection: false, notice: nil)
    }

    @objc private func menuHistory() { showSettings(.history) }
    @objc private func menuUpdates() {
        showSettings(.general)
        if Updater.shared.available == nil { Task { await Updater.shared.check() } }
    }
    @objc private func menuSettings() { showSettings(.general) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Settings window

    func showSettings(_ tab: SettingsTab) {
        store.settingsTab = tab
        if settingsWindow == nil {
            // Borderless glass, like the panel, but a normal window: it activates Tidy and
            // takes part in ⌘W and Mission Control.
            let window = GlassWindow(
                contentRect: NSRect(origin: .zero, size: SettingsView.size),
                styleMask: [.borderless, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "Tidy Settings"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store) { [weak window] in
                window?.performClose(nil)
            })
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Main menu (invisible, but gives text fields cut/copy/paste/undo)

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "Tidy")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

/// A borderless window that still behaves like a normal one: it can be key and main, and
/// ⌘W / the × close it (performClose would otherwise beep without a title-bar close button).
final class GlassWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }
}
