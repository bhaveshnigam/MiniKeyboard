import Foundation

/// Standard HID keyboard modifier bitmask, stored at `record[10 + 2n]`.
///
/// Bit 0 = Ctrl was confirmed directly in `Traversal_Key_Txt`
/// (`testb $0x1, %al` guarding the literal `"Ctrl+"`); the remaining bits follow
/// the HID Boot Keyboard convention the firmware is built on.
public struct Modifiers: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let leftControl  = Modifiers(rawValue: 1 << 0)
    public static let leftShift    = Modifiers(rawValue: 1 << 1)
    public static let leftOption   = Modifiers(rawValue: 1 << 2)
    public static let leftCommand  = Modifiers(rawValue: 1 << 3)
    public static let rightControl = Modifiers(rawValue: 1 << 4)
    public static let rightShift   = Modifiers(rawValue: 1 << 5)
    public static let rightOption  = Modifiers(rawValue: 1 << 6)
    public static let rightCommand = Modifiers(rawValue: 1 << 7)

    /// Left-hand aliases, which is what a user means by "ctrl" or "cmd".
    public static let control = leftControl
    public static let shift   = leftShift
    public static let option  = leftOption
    public static let command = leftCommand

    /// Parses one modifier token. Accepts both Mac and PC spellings.
    public static func named(_ token: String) -> Modifiers? {
        switch token.lowercased() {
        case "ctrl", "control", "lctrl":     return .leftControl
        case "rctrl", "rightctrl":           return .rightControl
        case "shift", "lshift":              return .leftShift
        case "rshift", "rightshift":         return .rightShift
        case "alt", "opt", "option", "lalt": return .leftOption
        case "ralt", "rightalt":             return .rightOption
        case "cmd", "command", "win", "gui", "meta", "super", "lgui":
            return .leftCommand
        case "rcmd", "rightcmd", "rgui":     return .rightCommand
        default: return nil
        }
    }

    /// Canonical `ctrl+shift+` style prefix, in a stable order.
    public var displayPrefix: String {
        var parts: [String] = []
        if contains(.leftControl)  { parts.append("ctrl") }
        if contains(.rightControl) { parts.append("rctrl") }
        if contains(.leftShift)    { parts.append("shift") }
        if contains(.rightShift)   { parts.append("rshift") }
        if contains(.leftOption)   { parts.append("alt") }
        if contains(.rightOption)  { parts.append("ralt") }
        if contains(.leftCommand)  { parts.append("cmd") }
        if contains(.rightCommand) { parts.append("rcmd") }
        return parts.isEmpty ? "" : parts.joined(separator: "+") + "+"
    }
}
