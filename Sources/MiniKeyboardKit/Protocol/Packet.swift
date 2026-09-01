import Foundation

/// Byte-exact encoder and decoder for the pad's wire format.
///
/// Every function here is pure, so the whole protocol is testable with no
/// hardware attached. This mirrors `Widget::HID_write` and
/// `Widget::read_Hidkey_Data` from the original binary.
public enum Packet {

    /// Wraps a payload in a zero-padded 65-byte output report.
    public static func report(_ payload: [UInt8]) -> [UInt8] {
        precondition(payload.count <= Wire.outputReportLength - 1,
                     "payload of \(payload.count) exceeds the 64-byte report body")
        var buf = [UInt8](repeating: 0, count: Wire.outputReportLength)
        buf[0] = Wire.reportID
        buf.replaceSubrange(1..<(1 + payload.count), with: payload)
        return buf
    }

    /// `03 FB FB FB` — ask the pad how many keys and knobs it has.
    public static func queryGeometry() -> [UInt8] {
        report([Wire.Command.query, Wire.Command.query, Wire.Command.query])
    }

    /// `03 FA <maxKeys> <maxKnobs> <layer>` — ask the pad to dump one whole layer.
    ///
    /// `Read_configuration_clicked` calls `read_Hidkey_Data(3, 0x0F, 3)`: three
    /// layers, and the constants 0x0F/0x03 as the key and knob ceilings. The
    /// device answers with a burst of records, one HID report each, rather than
    /// one reply per request.
    public static func readLayer(_ layer: Int,
                                 maxKeys: UInt8 = 0x0F,
                                 maxKnobs: UInt8 = 0x03) -> [UInt8] {
        report([Wire.Command.read, maxKeys, maxKnobs, UInt8(layer + 1)])
    }

    /// `03 FD FE FF` — commit the current transaction.
    public static func commit() -> [UInt8] {
        report([Wire.Command.program, 0xFE, 0xFF])
    }

    /// `03 EF EF` — reboot into the firmware bootloader. Destructive.
    public static func enterBootloader() -> [UInt8] {
        report([Wire.Command.bootloader, Wire.Command.bootloader])
    }

    /// Builds the 50-byte key record.
    ///
    /// - Parameters:
    ///   - keyIndex: 1-based physical key index.
    ///   - layer: 0-based layer; stored on the wire as `layer + 1`.
    public static func record(keyIndex: UInt8, layer: Int, action: KeyAction) -> [UInt8] {
        var rec = [UInt8](repeating: 0, count: Wire.recordLength)
        rec[Wire.Field.command]  = Wire.Command.program
        rec[Wire.Field.keyIndex] = keyIndex
        rec[Wire.Field.layer]    = UInt8(layer + 1)
        rec[Wire.Field.mode]     = action.mode.rawValue

        switch action {
        case .none:
            rec[Wire.Field.stepCount] = 0

        case .keyboard(let chords):
            let steps = Array(chords.prefix(Wire.maxMacroSteps))
            rec[Wire.Field.stepCount] = UInt8(steps.count)
            for (n, chord) in steps.enumerated() {
                rec[Wire.Field.steps + 2 * n]     = chord.modifiers.rawValue
                rec[Wire.Field.steps + 2 * n + 1] = chord.usage
            }

        case .media(let usage):
            // 16-bit consumer usage, little endian.
            rec[Wire.Field.stepCount] = 1
            rec[Wire.Field.steps]     = UInt8(usage & 0xFF)
            rec[Wire.Field.steps + 1] = UInt8(usage >> 8)

        case .mouse(let buttons, let wheel):
            // The pad stores a 4-byte mouse payload — buttons, wheel, x, y —
            // and puts its length in the count field rather than a step count.
            rec[Wire.Field.stepCount] = 4
            rec[Wire.Field.steps]     = buttons
            rec[Wire.Field.steps + 1] = UInt8(bitPattern: wheel)
        }
        return rec
    }

    /// A full 65-byte program-key report.
    public static func programKey(keyIndex: UInt8, layer: Int, action: KeyAction) -> [UInt8] {
        report(record(keyIndex: keyIndex, layer: layer, action: action))
    }

    /// Decodes a 50-byte record (or a longer input report) back into an action.
    public static func decode(record rec: [UInt8]) -> KeyAction {
        guard rec.count >= Wire.Field.steps + 2 else { return .none }
        let count = Int(rec[Wire.Field.stepCount])
        guard count > 0, let mode = KeyMode(rawValue: rec[Wire.Field.mode]) else { return .none }

        switch mode {
        case .keyboard:
            var chords: [Chord] = []
            for n in 0..<min(count, Wire.maxMacroSteps) {
                let mi = Wire.Field.steps + 2 * n
                guard mi + 1 < rec.count else { break }
                let usage = rec[mi + 1]
                let mods = Modifiers(rawValue: rec[mi])
                // A step with neither modifier nor usage is padding.
                if usage == 0 && mods.isEmpty { continue }
                chords.append(Chord(modifiers: mods, usage: usage))
            }
            return chords.isEmpty ? .none : .keyboard(chords)

        case .media:
            let usage = UInt16(rec[Wire.Field.steps])
                      | UInt16(rec[Wire.Field.steps + 1]) << 8
            return usage == 0 ? .none : .media(usage)

        case .mouse:
            return .mouse(buttons: rec[Wire.Field.steps],
                          wheel: Int8(bitPattern: rec[Wire.Field.steps + 1]))
        }
    }

    /// Strips the leading HID report-ID byte from a device reply, leaving a
    /// record that lines up with the write layout.
    ///
    /// Replies come back as `03 FA <index> <layer> <mode> …` — the same record
    /// the host sends, shifted one byte by the report ID and with `FA` in place
    /// of the `FD` command.
    public static func strip(_ response: [UInt8]) -> [UInt8] {
        guard let first = response.first, first == Wire.reportID else { return response }
        return Array(response.dropFirst())
    }

    /// The key index a record claims to describe (`record[1]`), or nil if the
    /// report is not a key record.
    public static func keyIndex(of rec: [UInt8]) -> Int? {
        guard rec.count > Wire.Field.layer,
              rec[Wire.Field.command] == Wire.Command.program
                || rec[Wire.Field.command] == Wire.Command.read
        else { return nil }
        let index = Int(rec[Wire.Field.keyIndex])
        return index > 0 ? index : nil
    }

    /// The 1-based layer a record claims to describe (`record[2]`).
    public static func layer(of rec: [UInt8]) -> Int? {
        guard rec.count > Wire.Field.layer else { return nil }
        let l = Int(rec[Wire.Field.layer])
        return (1...Wire.layerCount).contains(l) ? l - 1 : nil
    }

    /// Parses the response to `queryGeometry()`.
    /// `Read_KeyBoard_KeyNum` reads `resp[2]` and `resp[3]`.
    public static func decodeGeometry(_ response: [UInt8]) -> Geometry? {
        guard response.count >= 4 else { return nil }
        return Geometry(keyCount: Int(response[2]), knobCount: Int(response[3]))
    }
}

/// Physical layout reported by the device.
public struct Geometry: Sendable, Hashable, Codable {
    public var keyCount: Int
    public var knobCount: Int

    public init(keyCount: Int, knobCount: Int) {
        self.keyCount = keyCount
        self.knobCount = knobCount
    }

    /// Each knob contributes three bindings: counter-clockwise, press, clockwise.
    public var totalBindings: Int { keyCount + knobCount * 3 }

    /// e.g. "6 keys + 2 knobs"
    public var describe: String {
        knobCount == 0 ? "\(keyCount) keys" : "\(keyCount) keys + \(knobCount) knobs"
    }
}
