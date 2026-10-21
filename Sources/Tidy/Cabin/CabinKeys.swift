// Copied from Cabin 0.23.0 (tmass1/cabin, swift/Sources/CabinKit) by scripts/swift.mjs --sync. Don't edit here: change Cabin, then sync.
import Foundation

/// Keys written the Mac's way: modifiers as glyphs in Apple's order (⌃⌥⇧⌘), then the key.
/// The same rules as Cabin's `Kbd` on the web, so a shortcut reads the same in a web app and a native one.
public enum CabinKeys {
    /// Apple's order for modifiers.
    public static let modifierOrder = ["⌃", "⌥", "⇧", "⌘"]

    static let glyphs: [String: String] = [
        "ctrl": "⌃", "control": "⌃", "alt": "⌥", "option": "⌥", "opt": "⌥", "shift": "⇧",
        "cmd": "⌘", "command": "⌘", "meta": "⌘", "super": "⌘", "commandorcontrol": "⌘", "cmdorctrl": "⌘",
        "enter": "↩", "return": "↩", "esc": "esc", "escape": "esc", "tab": "⇥", "space": "Space",
        "backspace": "⌫", "delete": "⌫", "del": "⌦", "up": "↑", "down": "↓", "left": "←", "right": "→",
        "arrowup": "↑", "arrowdown": "↓", "arrowleft": "←", "arrowright": "→",
        "pageup": "⇞", "pagedown": "⇟", "home": "↖", "end": "↘",
    ]
    static let names: [String: String] = [
        "⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command", "↩": "Return", "⇥": "Tab", "⌫": "Delete",
        "↑": "Up", "↓": "Down", "←": "Left", "→": "Right", "esc": "Escape",
    ]

    /// "Cmd+Shift+K", "⌘⇧K", "esc", "F5" → ["⇧", "⌘", "K"]: glyphs, modifiers first in Apple's order.
    public static func split(_ keys: String) -> [String] {
        let s = keys.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return [] }
        let parts: [String]
        if s.count > 1 && s.contains("+") {
            parts = s.split(separator: "+").map(String.init)
        } else if glyphs[s.lowercased()] != nil || isWord(s) {
            parts = [s]                                   // "esc", "Space", "F5"
        } else {
            parts = s.filter { !$0.isWhitespace }.map { String($0) }   // "⌘⇧K"
        }
        return ordered(parts)
    }

    /// Already-separate keys (["cmd", "k"]) → glyphs in Apple's order.
    public static func split(_ parts: [String]) -> [String] { ordered(parts) }

    /// "⇧⌘K": the keys as one string, for a menu or a help tag.
    public static func display(_ keys: String) -> String { split(keys).joined() }

    /// "Shift Command K": what VoiceOver should say.
    public static func spoken(_ keys: String) -> String { split(keys).map { names[$0] ?? $0 }.joined(separator: " ") }

    /// Why a shortcut can't be global (it would stop typing everywhere, or take every app's ⌘-letter), or nil when it can.
    /// `modifiers` are glyphs or names ("⌘", "cmd"); `key` is the key ("C", "F5", "Space").
    public static func globalShortcutProblem(modifiers: [String], key: String) -> String? {
        let mods = Set(split(modifiers))
        if key.count >= 2, key.first == "F", Int(key.dropFirst()) != nil { return nil }   // function keys stand alone
        if mods.isDisjoint(with: ["⌘", "⌥", "⌃"]) { return "Add ⌘, ⌥ or ⌃: on its own the key would stop typing everywhere." }
        if mods == ["⌘"] { return "⌘ and one key belongs to every app’s menus. Add ⌥, ⌃ or ⇧." }
        return nil
    }

    static func isWord(_ s: String) -> Bool {
        guard s.count > 1, let first = s.unicodeScalars.first, CharacterSet.letters.contains(first), first.isASCII else { return false }
        return s.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    static func ordered(_ parts: [String]) -> [String] {
        let glyphed = parts.map { part -> String in
            let k = part.trimmingCharacters(in: .whitespaces)
            if let g = glyphs[k.lowercased()] { return g }
            return k.count == 1 ? k.uppercased() : k
        }
        let mods = modifierOrder.filter { glyphed.contains($0) }
        return mods + glyphed.filter { !modifierOrder.contains($0) }
    }
}
