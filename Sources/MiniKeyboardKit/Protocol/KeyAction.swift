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
    case media(UInt16)
    /// A mouse button and/or wheel delta, optionally with modifiers held.
    case mouse(modifiers: Modifiers = [], buttons: UInt8, wheel: Int8)

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

        // A mouse action may be prefixed with modifiers: "ctrl+mouse:wheelup".
        if let range = raw.lowercased().range(of: "mouse:") {
            var mods: Modifiers = []
            let prefix = String(raw[raw.startIndex..<range.lowerBound])
            for token in prefix.split(separator: "+") where !token.isEmpty {
                guard let m = Modifiers.named(String(token)) else {
                    throw ActionParseError.unknownMouseAction(String(token))
                }
                mods.insert(m)
            }
            let name = String(raw[range.upperBound...]).lowercased()
            switch name {
            case "wheelup":   return .mouse(modifiers: mods, buttons: 0, wheel: 1)
            case "wheeldown": return .mouse(modifiers: mods, buttons: 0, wheel: -1)
            // The pad has no horizontal wheel. macOS pans when Shift is held
            // with a vertical one, which is what the original offers as
            // "Shift+Mouse Up/Down", so these are aliases for that.
            case "scrollright":
                return .mouse(modifiers: mods.union(.leftShift), buttons: 0, wheel: 1)
            case "scrollleft":
                return .mouse(modifiers: mods.union(.leftShift), buttons: 0, wheel: -1)
            default:
                guard let b = MouseUsage.buttons[name] else {
                    throw ActionParseError.unknownMouseAction(name)
                }
                return .mouse(modifiers: mods, buttons: b, wheel: 0)
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
        case .mouse(let mods, let buttons, let wheel):
            // Shift plus a wheel is how horizontal scrolling is expressed.
            if wheel != 0, mods == .leftShift {
                return wheel > 0 ? "mouse:scrollright" : "mouse:scrollleft"
            }
            let prefix = mods.displayPrefix
            if wheel > 0 { return prefix + "mouse:wheelup" }
            if wheel < 0 { return prefix + "mouse:wheeldown" }
            return prefix + "mouse:"
                 + (MouseUsage.buttonNames[buttons] ?? String(format: "0x%02X", buttons))
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
