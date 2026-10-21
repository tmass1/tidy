import AppKit
import Carbon

/// A global keyboard shortcut, stored in Carbon terms so it can be registered system-wide.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let defaultCleanup = Shortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | optionKey),
        key: "C"
    )

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// Builds a shortcut from a key press in the recorder. Returns nil for presses that
    /// would make a bad global shortcut (plain letters with no modifier, etc.).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }

        let code = Int(event.keyCode)
        let isFunctionKey = Shortcut.functionKeys[code] != nil
        if !isFunctionKey && (mods & UInt32(cmdKey | controlKey | optionKey)) == 0 { return nil }

        let label = Shortcut.functionKeys[code]
            ?? Shortcut.specialKeys[code]
            ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !label.trimmed.isEmpty || code == kVK_Space else { return nil }
        self.init(keyCode: UInt32(code), modifiers: mods, key: label)
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
    ]

    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
    ]
}

/// Registers one system-wide hotkey through Carbon. This is the same mechanism
/// Spotlight-style launchers use, and it takes priority over app shortcuts.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var action: (@MainActor () -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5449_4459), id: 1) // 'TIDY'
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return status == OSStatus(noErr)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    fileprivate func fire() { action?() }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in HotKeyCenter.shared.fire() }
            return OSStatus(noErr)
        }, 1, &spec, nil, &handlerRef)
    }
}
