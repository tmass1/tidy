import AppKit
import ApplicationServices
import Carbon

/// Reads the current selection from the frontmost app (by sending ⌘C) and pastes text
/// back (by sending ⌘V), leaving the user's clipboard the way it was.
enum Selection {
    static func isTrusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func copySelection() async -> String? {
        await waitForModifierRelease()
        let pb = NSPasteboard.general
        let saved = snapshot()
        let before = pb.changeCount
        press(CGKeyCode(kVK_ANSI_C))

        var text: String?
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before {
                try? await Task.sleep(nanoseconds: 20_000_000)
                text = pb.string(forType: .string)
                break
            }
        }
        if pb.changeCount != before { restore(saved) }
        guard let text, !text.trimmed.isEmpty else { return nil }
        return text
    }

    @MainActor
    static func paste(_ text: String, restoreClipboard: Bool) async {
        let saved = restoreClipboard ? snapshot() : nil
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        await waitForModifierRelease()
        press(CGKeyCode(kVK_ANSI_V))
        if let saved {
            try? await Task.sleep(nanoseconds: 800_000_000)
            restore(saved)
        }
    }

    // MARK: - Helpers

    /// The hotkey fires while ⌥⌘ are still held. Sending ⌘C before they're released would
    /// arrive as ⌥⌘C, so wait (briefly) for the user to let go.
    private static func waitForModifierRelease() async {
        for _ in 0..<60 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty { return }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    private static func snapshot() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) { data[type] = d }
            }
            return data
        }
    }

    @MainActor
    private static func restore(_ snapshot: Snapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }
}
