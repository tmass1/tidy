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
        controller.openSettings = { [weak self] in self?.showSettings(.general) }
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()

        HotKeyCenter.shared.action = { [weak self] in self?.trigger() }
        store.registerHotKey()

        if !store.hasAPIKey { showSettings(.general) }
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
    @objc private func menuSettings() { showSettings(.general) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Settings window

    func showSettings(_ tab: SettingsTab) {
        store.settingsTab = tab
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Tidy"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store))
            window.setContentSize(NSSize(width: 760, height: 580))
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

        NSApp.mainMenu = main
    }
}
