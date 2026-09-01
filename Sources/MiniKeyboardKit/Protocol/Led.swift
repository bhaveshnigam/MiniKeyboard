import Foundation

/// Backlight setting for one layer.
///
/// Reverse-engineered from `Widget::SetRgb_Led_Key`, which packs both values
/// into a single byte: the low nibble is the mode, the high nibble the colour.
/// The original masks one nibble and ORs in the other depending on whether the
/// incoming value is above 0x0F, and forces the colour to 5 when it would
/// otherwise be zero.
public struct LedSetting: Equatable, Sendable, Codable, Hashable {
    /// 0...5. The firmware exposes six modes (`LED_Mode_0` … `LED_Mode_5`).
    public var mode: Int
    /// 1...7 (`LED_color_1` … `LED_color_7`). Colour 0 is not valid — the
    /// original substitutes 5.
    public var color: Int

    public init(mode: Int, color: Int = 5) {
        self.mode = Self.clampMode(mode)
        self.color = Self.clampColor(color)
    }

    public static let modeRange = 0...5

    /// Effect names, observed on a live 12-key pad.
    public static let modeNames = [
        "Off",              // 0 — no light at all
        "Solid",            // 1 — every key lit in the chosen colour
        "Wave",             // 2 — lights run up the keys one by one, then back
        "Wave Reverse",     // 3 — the same sequence in the opposite order
        "Reactive",         // 4 — only the key being pressed lights up
        "Rainbow",          // 5 — every colour at once, which reads as white
    ]

    /// Colour names, from the original's own labels.
    public static let colorNames = [
        1: "Red", 2: "Orange", 3: "Yellow", 4: "Green",
        5: "Cyan", 6: "Blue", 7: "Purple",
    ]

    public var modeName: String {
        Self.modeNames.indices.contains(mode) ? Self.modeNames[mode] : "Mode \(mode)"
    }
    public var colorName: String { Self.colorNames[color] ?? "Colour \(color)" }

    /// Mode 5 mixes every colour, and mode 0 is off, so neither uses the
    /// colour field.
    public var usesColor: Bool { mode != 0 && mode != 5 }

    public static func mode(named name: String) -> Int? {
        modeNames.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    public static func color(named name: String) -> Int? {
        colorNames.first { $0.value.caseInsensitiveCompare(name) == .orderedSame }?.key
    }
    public static let colorRange = 1...7

    static func clampMode(_ v: Int) -> Int { min(max(v, modeRange.lowerBound), modeRange.upperBound) }
    static func clampColor(_ v: Int) -> Int {
        v == 0 ? 5 : min(max(v, colorRange.lowerBound), colorRange.upperBound)
    }

    /// The single packed byte the firmware stores.
    public var packed: UInt8 {
        UInt8((color << 4) | mode)
    }

    public init(packed: UInt8) {
        let high = Int(packed >> 4)
        self.mode = Self.clampMode(Int(packed & 0x0F))
        self.color = Self.clampColor(high)
    }

    /// Off is mode 0 in every firmware seen so far.
    public static let off = LedSetting(mode: 0, color: 5)

    public var describe: String {
        usesColor ? "\(modeName), \(colorName)" : modeName
    }
}

extension Packet {
    /// `03 FE B0 <layer> …` — the backlight record.
    ///
    /// It lives in slot 0 of each layer's record table, which is why key
    /// records start at index 1 and why a layer read never returns it.
    public static func ledRecord(_ setting: LedSetting, layer: Int) -> [UInt8] {
        var rec = [UInt8](repeating: 0, count: Wire.recordLength)
        rec[Wire.Field.command]  = Wire.Command.led
        rec[Wire.Field.keyIndex] = Wire.Command.ledSub
        rec[Wire.Field.layer]    = UInt8(layer + 1)
        rec[Wire.Field.mode]     = KeyMode.led.rawValue
        rec[Wire.Field.stepCount] = 1
        rec[Wire.Field.steps + 1] = setting.packed
        return rec
    }

    public static func led(_ setting: LedSetting, layer: Int) -> [UInt8] {
        report(ledRecord(setting, layer: layer))
    }
}
