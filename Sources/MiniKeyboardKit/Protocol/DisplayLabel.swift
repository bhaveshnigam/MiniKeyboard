import Foundation

/// Human-readable names for bindings.
///
/// These are presentation only. `displayName` stays the canonical token that
/// round-trips through the parser and through profile JSON; `displayLabel` is
/// what a person should read on a keycap. Keeping them apart means the UI can
/// say "Num +" without the file format drifting away from what you can type.
extension HIDUsage {
    private static let labels: [UInt8: String] = [
        0x28: "Return", 0x29: "Esc", 0x2A: "⌫", 0x2B: "Tab", 0x2C: "Space",
        0x39: "Caps Lock",
        0x46: "Print Screen", 0x47: "Scroll Lock", 0x48: "Pause",
        0x49: "Insert", 0x4A: "Home", 0x4B: "Page Up",
        0x4C: "⌦", 0x4D: "End", 0x4E: "Page Down",
        0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
        0x53: "Num Lock",
        0x54: "Num ÷", 0x55: "Num ×", 0x56: "Num −", 0x57: "Num +",
        0x58: "Num ⏎",
        0x59: "Num 1", 0x5A: "Num 2", 0x5B: "Num 3", 0x5C: "Num 4",
        0x5D: "Num 5", 0x5E: "Num 6", 0x5F: "Num 7", 0x60: "Num 8",
        0x61: "Num 9", 0x62: "Num 0", 0x63: "Num .",
        0x65: "Menu",
    ]

    /// A label suited to a keycap: "Num +" rather than "kpplus", "A" rather
    /// than "a", the arrow glyph rather than the word.
    public static func label(for code: UInt8) -> String {
        if let known = labels[code] { return known }
        let name = name(for: code)
        // Letters read better capitalised; punctuation and digits stay literal.
        if name.count == 1, name.first!.isLetter { return name.uppercased() }
        if name.first == "f", Int(name.dropFirst()) != nil { return name.uppercased() }
        return name
    }
}

extension Modifiers {
    /// Mac modifier glyphs in the conventional ⌃⌥⇧⌘ order.
    public var displayGlyphs: String {
        var parts: [String] = []
        if contains(.leftControl)  { parts.append("⌃") }
        if contains(.rightControl) { parts.append("R⌃") }
        if contains(.leftOption)   { parts.append("⌥") }
        if contains(.rightOption)  { parts.append("R⌥") }
        if contains(.leftShift)    { parts.append("⇧") }
        if contains(.rightShift)   { parts.append("R⇧") }
        if contains(.leftCommand)  { parts.append("⌘") }
        if contains(.rightCommand) { parts.append("R⌘") }
        return parts.joined()
    }
}

extension Chord {
    public var displayLabel: String {
        modifiers.displayGlyphs + HIDUsage.label(for: usage)
    }
}

extension MediaUsage {
    private static let labels: [UInt16: String] = [
        0x00CD: "Play / Pause", 0x00B5: "Next Track", 0x00B6: "Previous Track",
        0x00B7: "Stop", 0x00B8: "Eject", 0x00E2: "Mute",
        0x00E9: "Volume Up", 0x00EA: "Volume Down",
        0x006F: "Brightness Up", 0x0070: "Brightness Down",
        0x0183: "Media Player", 0x018A: "Mail", 0x0192: "Calculator",
        0x0194: "File Explorer", 0x0221: "Search", 0x0223: "Browser Home",
        0x0224: "Browser Back", 0x0225: "Browser Forward",
        0x0227: "Refresh", 0x022A: "Bookmarks",
    ]

    public static func label(for code: UInt16) -> String {
        labels[code] ?? name(for: code)
    }
}

extension MouseUsage {
    private static let labels: [UInt8: String] = [
        0x01: "Left Click", 0x02: "Right Click", 0x04: "Middle Click",
    ]

    public static func label(for buttons: UInt8) -> String {
        labels[buttons] ?? String(format: "Button 0x%02X", buttons)
    }
}

extension KeyAction {
    /// What a person should read. Use `displayName` when the value has to be
    /// parsed back or written to a profile.
    public var displayLabel: String {
        switch self {
        case .none:
            return "—"
        case .keyboard(let chords):
            guard !chords.isEmpty else { return "—" }
            // Macro steps read as a sequence, so an arrow beats a comma.
            return chords.map(\.displayLabel).joined(separator: " → ")
        case .media(let usage):
            return MediaUsage.label(for: usage)
        case .mouse(let mods, let buttons, let wheel):
            if wheel != 0, mods == .leftShift {
                return wheel > 0 ? "Scroll Right" : "Scroll Left"
            }
            let prefix = mods.displayGlyphs
            if wheel > 0 { return prefix + "Wheel Up" }
            if wheel < 0 { return prefix + "Wheel Down" }
            return prefix + MouseUsage.label(for: buttons)
        }
    }
}
