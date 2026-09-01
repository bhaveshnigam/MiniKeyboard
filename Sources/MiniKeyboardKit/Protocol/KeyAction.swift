import Foundation

/// One step of a keyboard macro: a chord.
public struct Chord: Sendable, Hashable, Codable {
    public var modifiers: Modifiers
    public var usage: UInt8

    public init(modifiers: Modifiers = [], usage: UInt8) {
        self.modifiers = modifiers
        self.usage = usage
    }

    /// Parses `"ctrl+shift+a"`, `"cmd+c"`, `"f5"`, or a bare `"a"`.
    /// A trailing lone `+` is treated as the literal plus key.
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var mods: Modifiers = []
        var tokens = trimmed.lowercased().split(separator: "+", omittingEmptySubsequences: false)
                            .map(String.init)

        // "ctrl++" -> tokens ["ctrl", "", ""]; the key is the literal "+".
        if tokens.count >= 2, tokens.last == "", tokens[tokens.count - 2] == "" {
            tokens.removeLast()
            tokens[tokens.count - 1] = "="   // shift+= is plus; store the physical key
            mods.insert(.leftShift)
        }
        tokens.removeAll { $0.isEmpty }
        guard let keyToken = tokens.last else { return nil }

        for token in tokens.dropLast() {
            guard let m = Modifiers.named(token) else { return nil }
            mods.insert(m)
        }
        guard let code = HIDUsage.code(for: keyToken) else { return nil }
        self.modifiers = mods
        self.usage = code
    }

    public var displayName: String {
        modifiers.displayPrefix + HIDUsage.name(for: usage)
    }
}

/// What a physical key or knob direction does.
public enum KeyAction: Sendable, Hashable, Codable {
    /// Nothing — key is cleared.
    case none
    /// One or more chords played in sequence (up to `Wire.maxMacroSteps`).
    case keyboard([Chord])
    /// A consumer-page media control.
    case media(UInt8)
    /// A mouse button bitmask and/or wheel delta.
    case mouse(buttons: UInt8, wheel: Int8)

    public var mode: KeyMode {
        switch self {
        case .none, .keyboard: return .keyboard
        case .media:           return .media
        case .mouse:           return .mouse
        }
    }

    /// Parses the textual form used in profile JSON and on the CLI.
    ///
    /// - `"none"` / `""`
    /// - `"ctrl+c"` or `"ctrl+c, cmd+v"` for a multi-step macro
    /// - `"media:volumeup"`
    /// - `"mouse:left"`, `"mouse:wheelup"`, `"mouse:wheeldown"`
    public static func parse(_ text: String) throws -> KeyAction {
        let raw = text.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty || raw.lowercased() == "none" { return .none }

        if raw.lowercased().hasPrefix("media:") {
            let name = String(raw.dropFirst("media:".count))
            guard let code = MediaUsage.code(for: name) else {
                throw ActionParseError.unknownMediaKey(name)
            }
            return .media(code)
        }

        if raw.lowercased().hasPrefix("mouse:") {
            let name = String(raw.dropFirst("mouse:".count)).lowercased()
            switch name {
            case "wheelup":   return .mouse(buttons: 0, wheel: 1)
            case "wheeldown": return .mouse(buttons: 0, wheel: -1)
            default:
                guard let b = MouseUsage.buttons[name] else {
                    throw ActionParseError.unknownMouseAction(name)
                }
                return .mouse(buttons: b, wheel: 0)
            }
        }

        let steps = raw.split(separator: ",").map(String.init)
        guard steps.count <= Wire.maxMacroSteps else {
            throw ActionParseError.macroTooLong(steps.count)
        }
        var chords: [Chord] = []
        for step in steps {
            guard let chord = Chord(parsing: step) else {
                throw ActionParseError.unknownKey(step.trimmingCharacters(in: .whitespaces))
            }
            chords.append(chord)
        }
        return .keyboard(chords)
    }

    public var displayName: String {
        switch self {
        case .none:
            return "none"
        case .keyboard(let chords):
            return chords.isEmpty ? "none" : chords.map(\.displayName).joined(separator: ", ")
        case .media(let code):
            return "media:" + MediaUsage.name(for: code)
        case .mouse(let buttons, let wheel):
            if wheel > 0 { return "mouse:wheelup" }
            if wheel < 0 { return "mouse:wheeldown" }
            return "mouse:" + (MouseUsage.buttonNames[buttons] ?? String(format: "0x%02X", buttons))
        }
    }
}

public enum ActionParseError: Error, CustomStringConvertible, Equatable {
    case unknownKey(String)
    case unknownMediaKey(String)
    case unknownMouseAction(String)
    case macroTooLong(Int)

    public var description: String {
        switch self {
        case .unknownKey(let k):         return "unknown key or chord: \"\(k)\""
        case .unknownMediaKey(let k):    return "unknown media key: \"\(k)\""
        case .unknownMouseAction(let k): return "unknown mouse action: \"\(k)\""
        case .macroTooLong(let n):
            return "macro has \(n) steps; the firmware allows at most \(Wire.maxMacroSteps)"
        }
    }
}
