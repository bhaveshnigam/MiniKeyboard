import Foundation

/// HID Usage Table, page 0x07 (Keyboard/Keypad) — the codes written to
/// `record[11 + 2n]` when `record[3] == KeyMode.keyboard`.
public enum HIDUsage {
    /// Canonical name -> usage code.
    public static let byName: [String: UInt8] = {
        var t: [String: UInt8] = [:]

        // Letters: a = 0x04 ... z = 0x1D
        for (i, ch) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            t[String(ch)] = UInt8(0x04 + i)
        }
        // Digits: 1..9 = 0x1E..0x26, 0 = 0x27
        for (i, ch) in "123456789".enumerated() {
            t[String(ch)] = UInt8(0x1E + i)
        }
        t["0"] = 0x27

        let named: [String: UInt8] = [
            "enter": 0x28, "return": 0x28,
            "escape": 0x29, "esc": 0x29,
            "backspace": 0x2A, "delete": 0x2A,
            "tab": 0x2B,
            "space": 0x2C,
            "minus": 0x2D, "-": 0x2D,
            "equal": 0x2E, "=": 0x2E,
            "leftbracket": 0x2F, "[": 0x2F,
            "rightbracket": 0x30, "]": 0x30,
            "backslash": 0x31, "\\": 0x31,
            "semicolon": 0x33, ";": 0x33,
            "quote": 0x34, "'": 0x34,
            "grave": 0x35, "`": 0x35,
            "comma": 0x36, ",": 0x36,
            "period": 0x37, ".": 0x37,
            "slash": 0x38, "/": 0x38,
            "capslock": 0x39,
            "printscreen": 0x46, "prtsc": 0x46,
            "scrolllock": 0x47,
            "pause": 0x48,
            "insert": 0x49, "ins": 0x49,
            "home": 0x4A,
            "pageup": 0x4B, "pgup": 0x4B,
            "forwarddelete": 0x4C, "del": 0x4C,
            "end": 0x4D,
            "pagedown": 0x4E, "pgdn": 0x4E,
            "right": 0x4F, "left": 0x50, "down": 0x51, "up": 0x52,
            "numlock": 0x53,
            "kpslash": 0x54, "kpasterisk": 0x55, "kpminus": 0x56,
            "kpplus": 0x57, "kpenter": 0x58,
            "kp1": 0x59, "kp2": 0x5A, "kp3": 0x5B, "kp4": 0x5C, "kp5": 0x5D,
            "kp6": 0x5E, "kp7": 0x5F, "kp8": 0x60, "kp9": 0x61, "kp0": 0x62,
            "kpperiod": 0x63,
            "application": 0x65, "menu": 0x65,
        ]
        for (k, v) in named { t[k] = v }

        // Function keys: F1..F12 = 0x3A..0x45, F13..F24 = 0x68..0x73
        for i in 1...12 { t["f\(i)"] = UInt8(0x3A + i - 1) }
        for i in 13...24 { t["f\(i)"] = UInt8(0x68 + i - 13) }

        return t
    }()

    /// Usage code -> preferred display name (first canonical spelling wins).
    public static let names: [UInt8: String] = {
        // Preferred spellings, so `0x2A` shows as "backspace" not "delete".
        let preferred: [UInt8: String] = [
            0x28: "enter", 0x29: "esc", 0x2A: "backspace", 0x2C: "space",
            0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\",
            0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/",
            0x46: "printscreen", 0x49: "insert", 0x4B: "pageup",
            0x4C: "forwarddelete", 0x4E: "pagedown", 0x65: "menu",
        ]
        var t = preferred
        for (name, code) in byName where t[code] == nil {
            t[code] = name
        }
        return t
    }()

    public static func code(for name: String) -> UInt8? {
        byName[name.lowercased()]
    }

    public static func name(for code: UInt8) -> String {
        names[code] ?? String(format: "0x%02X", code)
    }
}

/// HID Usage Table, page 0x0C (Consumer) — used when `record[3] == KeyMode.media`.
///
/// The firmware stores a single-byte selector rather than the full 16-bit consumer
/// usage, so these are the pad's own media codes.
public enum MediaUsage {
    public static let byName: [String: UInt8] = [
        "playpause": 0x01, "play": 0x01, "pause": 0x01,
        "next": 0x02, "nexttrack": 0x02,
        "previous": 0x03, "prevtrack": 0x03, "prev": 0x03,
        "stop": 0x04,
        "mute": 0x05,
        "volumeup": 0x06, "volup": 0x06,
        "volumedown": 0x07, "voldown": 0x07,
        "email": 0x08,
        "calculator": 0x09, "calc": 0x09,
        "explorer": 0x0A, "files": 0x0A,
        "browser": 0x0B, "home": 0x0B,
        "back": 0x0C, "forward": 0x0D, "refresh": 0x0E,
        "search": 0x0F,
        "brightnessup": 0x10, "brightnessdown": 0x11,
        "screenshot": 0x12,
    ]

    public static let names: [UInt8: String] = [
        0x01: "playpause", 0x02: "next", 0x03: "previous", 0x04: "stop",
        0x05: "mute", 0x06: "volumeup", 0x07: "volumedown", 0x08: "email",
        0x09: "calculator", 0x0A: "explorer", 0x0B: "browser", 0x0C: "back",
        0x0D: "forward", 0x0E: "refresh", 0x0F: "search",
        0x10: "brightnessup", 0x11: "brightnessdown", 0x12: "screenshot",
    ]

    public static func code(for name: String) -> UInt8? { byName[name.lowercased()] }
    public static func name(for code: UInt8) -> String {
        names[code] ?? String(format: "0x%02X", code)
    }
}

/// Mouse actions — used when `record[3] == KeyMode.mouse`.
///
/// `record[10]` carries the button bitmask, `record[11]` the wheel delta
/// (signed; `Traversal_Key_Txt` dispatches on it via a jump table).
public enum MouseUsage {
    public static let buttons: [String: UInt8] = [
        "left": 0x01, "right": 0x02, "middle": 0x04,
        "back": 0x08, "forward": 0x10,
    ]
    public static let buttonNames: [UInt8: String] = [
        0x01: "left", 0x02: "right", 0x04: "middle",
        0x08: "back", 0x10: "forward",
    ]
}
