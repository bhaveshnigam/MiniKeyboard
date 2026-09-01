import Foundation

/// Low-level wire constants for the CH57x-family macro pad.
///
/// Reverse-engineered from the stock `MINI_KEYBOARD.app` (Qt 5.12.9, x86_64).
/// See `Widget::HID_write`, `Widget::read_Hidkey_Data`, `Widget::Read_KeyBoard_KeyNum`.
public enum Wire {
    /// USB vendor ID shared by every device in this family.
    public static let vendorID: Int = 0x1189

    /// Known product IDs, taken from the `_PID` / `_PID_GRU` tables in `__DATA,__data`.
    public static let productIDs: [Int] = [
        0x8840, 0x8842, 0x8830, 0x8831, 0x8832, 0x8833, 0x8850, 0x8851,
    ]

    /// Every packet is prefixed with this HID report ID.
    public static let reportID: UInt8 = 0x03

    /// Output reports are always this long: report ID + 64 payload bytes.
    public static let outputReportLength = 65

    /// Input reports are read 64 bytes at a time.
    public static let inputReportLength = 64

    /// A single key's configuration record, as stored in `_PHY_KEY_Value`.
    public static let recordLength = 50

    /// Layers supported by the firmware (`_PHY_KEY_Value` is `[3][60][50]`).
    public static let layerCount = 3

    /// Maximum addressable keys per layer.
    public static let maxKeysPerLayer = 60

    /// Physical keys occupy a fixed block of slots regardless of how many the
    /// pad actually has; knobs start after it. Confirmed on a 12-key/2-knob pad,
    /// whose knob bindings read back at slots 16-21.
    public static let keySlotCount = 15
    public static let knobSlotBase = 16
    /// Each knob contributes counter-clockwise, press, clockwise.
    public static let slotsPerKnob = 3

    /// Largest delay the original's spin box allows, in milliseconds.
    public static let maxDelay = 6000

    /// Maximum steps in a single key's macro (`cmpq $0x12` in `Traversal_Key_Txt`).
    public static let maxMacroSteps = 18

    public enum Command {
        /// Program a key. Also `FD FE FF` as the end-of-transaction commit.
        public static let program: UInt8 = 0xFD
        /// Read back a key's configuration.
        public static let read: UInt8 = 0xFA
        /// Query key/knob geometry.
        public static let query: UInt8 = 0xFB
        /// Set keyboard variant.
        public static let setVariant: UInt8 = 0xFC
        /// Enter the firmware bootloader. Destructive — gated behind an explicit call.
        public static let bootloader: UInt8 = 0xEF
        /// Backlight record, written to slot 0 of a layer.
        public static let led: UInt8 = 0xFE
        /// Sub-command that follows `led`.
        public static let ledSub: UInt8 = 0xB0
    }

    /// Byte offsets within a 50-byte key record.
    public enum Field {
        public static let command = 0
        public static let keyIndex = 1
        public static let layer = 2
        public static let mode = 3
        /// 16-bit little-endian inter-keystroke delay, in milliseconds.
        /// `Key_Delay_Page_Opt` writes the spin box value across these two bytes.
        public static let delayLow = 4
        public static let delayHigh = 5
        public static let stepCount = 9
        /// First macro step. Step `n` is `(modifier: steps + 2n, usage: steps + 2n + 1)`.
        public static let steps = 10
        /// Mouse records reuse the step area: modifiers, buttons, x, y, wheel.
        public static let mouseModifiers = 10
        public static let mouseButtons = 11
        public static let mouseWheel = 14
    }
}

extension Wire {
    /// Wire slot indices for a given geometry: keys first, then three slots per
    /// knob starting at `knobSlotBase`.
    public static func slotIndices(for geometry: Geometry?) -> [Int] {
        let geo = geometry ?? Geometry(keyCount: keySlotCount, knobCount: 3)
        var slots = Array(1...max(geo.keyCount, 1))
        for k in 0..<geo.knobCount {
            let base = knobSlotBase + k * slotsPerKnob
            slots.append(contentsOf: base..<(base + slotsPerKnob))
        }
        return slots
    }
}

/// What kind of input a key emits. Stored at `record[3]`.
public enum KeyMode: UInt8, Sendable, Codable, CaseIterable {
    case keyboard = 1
    case media = 2
    case mouse = 3
    /// A patch that sets only the inter-keystroke delay, leaving the key's
    /// action alone. The DelaySetting tab uses this.
    case delayPatch = 5
    /// The backlight record. `on_tabWidget_currentChanged` sets this mode and
    /// selects slot 0 when the RGB LED tab opens.
    case led = 8
}
