import Testing
import Foundation
@testable import MiniKeyboardKit

/// These assertions encode the layout recovered from the original x86_64 binary.
/// They are the contract the port must satisfy, and they run with no hardware.
@Suite("Wire format")
struct PacketTests {

    @Test("Reports are 65 bytes, report ID 0x03, zero padded")
    func reportShape() {
        let r = Packet.report([0xAA, 0xBB])
        #expect(r.count == Wire.outputReportLength)
        #expect(r[0] == 0x03)
        #expect(r[1] == 0xAA)
        #expect(r[2] == 0xBB)
        #expect(r[3...].allSatisfy { $0 == 0 })
    }

    /// `Read_KeyBoard_KeyNum`: movl $0xFBFBFB03 -> bytes 03 FB FB FB
    @Test("Geometry query is 03 FB FB FB")
    func geometryQuery() {
        let p = Packet.queryGeometry()
        #expect(Array(p[0..<4]) == [0x03, 0xFB, 0xFB, 0xFB])
    }

    /// `Read_configuration_clicked` calls `read_Hidkey_Data(3, 0x0F, 3)`,
    /// so the ceilings are 0x0F keys / 0x03 knobs and the varying byte is the layer.
    @Test("Read-layer request is 03 FA 0F 03 <layer>")
    func readRequest() {
        #expect(Array(Packet.readLayer(0)[0..<5]) == [0x03, 0xFA, 0x0F, 0x03, 0x01])
        #expect(Array(Packet.readLayer(2)[0..<5]) == [0x03, 0xFA, 0x0F, 0x03, 0x03])
    }

    @Test("Records identify their own key and layer")
    func recordSelfIdentifies() {
        let rec = Packet.record(keyIndex: 9, layer: 2, action: .keyboard([Chord(usage: 0x04)]))
        #expect(Packet.keyIndex(of: rec) == 9)
        #expect(Packet.layer(of: rec) == 2)
    }

    /// `HID_write` tail: movw $0xFEFD then movb $0xFF.
    @Test("Commit packet is 03 FD FE FF")
    func commitPacket() {
        let p = Packet.commit()
        #expect(Array(p[0..<4]) == [0x03, 0xFD, 0xFE, 0xFF])
    }

    @Test("Bootloader packet is 03 EF EF")
    func bootloaderPacket() {
        #expect(Array(Packet.enterBootloader()[0..<3]) == [0x03, 0xEF, 0xEF])
    }

    /// Record header from `Widget::on_changeButtonGroup`:
    ///   rec[0] = 0xFD, rec[1] = key index, rec[2] = layer + 1
    /// and `SetBasicKey`: rec[3] = mode, rec[9] = step count,
    /// rec[10 + 2n] = modifier, rec[11 + 2n] = usage.
    @Test("Key record header matches the reversed layout")
    func recordHeader() {
        let rec = Packet.record(keyIndex: 5, layer: 1, action: .keyboard([
            Chord(modifiers: [.control, .shift], usage: 0x04)  // ctrl+shift+a
        ]))
        #expect(rec.count == 50)
        #expect(rec[0] == 0xFD)
        #expect(rec[1] == 5)
        #expect(rec[2] == 2)          // layer is 1-based on the wire
        #expect(rec[3] == 1)          // keyboard mode
        #expect(rec[9] == 1)          // one step
        #expect(rec[10] == 0b0000_0011) // ctrl | shift
        #expect(rec[11] == 0x04)      // usage for 'a'
        #expect(rec[4...8].allSatisfy { $0 == 0 })
    }

    @Test("Macro steps are laid out as consecutive (modifier, usage) pairs")
    func macroLayout() throws {
        let action = try KeyAction.parse("ctrl+c, ctrl+v, cmd+s")
        let rec = Packet.record(keyIndex: 1, layer: 0, action: action)
        #expect(rec[9] == 3)
        #expect(rec[10] == 0x01); #expect(rec[11] == 0x06) // ctrl + c
        #expect(rec[12] == 0x01); #expect(rec[13] == 0x19) // ctrl + v
        #expect(rec[14] == 0x08); #expect(rec[15] == 0x16) // cmd + s
    }

    @Test("Macros are capped at the firmware's 18 steps")
    func macroCap() {
        let chords = (0..<30).map { _ in Chord(usage: 0x04) }
        let rec = Packet.record(keyIndex: 1, layer: 0, action: .keyboard(chords))
        #expect(rec[9] == 18)
        // Last pair ends at offset 45; 46...49 stay reserved.
        #expect(rec[46...49].allSatisfy { $0 == 0 })
    }

    @Test("Media keys store a 16-bit consumer usage little endian")
    func mediaEncoding() throws {
        let media = Packet.record(keyIndex: 2, layer: 0,
                                  action: try KeyAction.parse("media:volumeup"))
        #expect(media[3] == 2)
        #expect(media[10] == 0xE9)   // Volume Increment, low byte
        #expect(media[11] == 0x00)

        let calc = Packet.record(keyIndex: 2, layer: 0,
                                 action: try KeyAction.parse("media:calculator"))
        #expect(calc[10] == 0x92)    // 0x0192 AL Calculator
        #expect(calc[11] == 0x01)
    }

    /// Confirmed against the original app, which shows "Mouse LeftKey" for a
    /// record whose byte 11 is 0x01.
    @Test("Mouse records put buttons at 11 and the wheel at 14")
    func mouseEncoding() throws {
        let mouse = Packet.record(keyIndex: 2, layer: 0,
                                  action: try KeyAction.parse("mouse:left"))
        #expect(mouse[3] == 3)
        #expect(mouse[9] == 4)       // payload length, not a step count
        #expect(mouse[10] == 0)      // no modifiers
        #expect(mouse[11] == 0x01)   // left button
        #expect(mouse[14] == 0)      // no wheel

        let wheel = Packet.record(keyIndex: 2, layer: 0,
                                  action: try KeyAction.parse("mouse:wheeldown"))
        #expect(wheel[11] == 0)
        #expect(Int8(bitPattern: wheel[14]) == -1)

        let modified = Packet.record(keyIndex: 2, layer: 0,
                                     action: try KeyAction.parse("ctrl+mouse:wheelup"))
        #expect(modified[10] == Modifiers.leftControl.rawValue)
        #expect(Int8(bitPattern: modified[14]) == 1)
    }

    /// Captured from a live 12-key / 2-knob pad. These are the exact bytes the
    /// firmware returned, so they pin the decoder to real hardware behaviour
    /// rather than to an assumption about the layout.
    @Test("Decodes reports captured from real hardware")
    func realCaptures() throws {
        func decode(_ hex: String) -> KeyAction {
            let bytes = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
            return Packet.decode(record: Packet.strip(bytes))
        }
        // key 1 -> keypad plus
        #expect(decode("03 FA 01 01 01 00 00 00 00 00 01 00 57") == .keyboard([Chord(usage: 0x57)]))
        // key 20 -> ctrl+up
        #expect(decode("03 FA 14 01 01 00 00 00 00 00 01 01 52")
                == .keyboard([Chord(modifiers: .leftControl, usage: 0x52)]))
        // knob 1 counter-clockwise -> volume down
        #expect(decode("03 FA 10 01 02 00 00 00 00 00 01 EA 00") == .media(0x00EA))
        // knob 1 press -> mute
        #expect(decode("03 FA 11 01 02 00 00 00 00 00 01 E2 00") == .media(0x00E2))
        // knob 2 clockwise -> brightness up
        #expect(decode("03 FA 15 01 02 00 00 00 00 00 01 6F 00") == .media(0x006F))
        // knob 1 press on layer 2 -> left click. The original app labels this
        // exact record "Mouse LeftKey", which is what pinned the layout down.
        #expect(decode("03 FA 11 02 03 00 00 00 00 00 04 00 01 00 00 00")
                == .mouse(buttons: 0x01, wheel: 0))
    }

    @Test("Records read back from hardware identify their own slot")
    func capturedHeaders() {
        let bytes = "03 FA 15 01 02 00 00 00 00 00 01 6F 00"
            .split(separator: " ").map { UInt8($0, radix: 16)! }
        let rec = Packet.strip(bytes)
        #expect(Packet.keyIndex(of: rec) == 21)   // 0x15, knob 2 clockwise
        #expect(Packet.layer(of: rec) == 0)       // wire layer 1 -> index 0
    }

    @Test("Knob slots start at a fixed base after the key block")
    func slotLayout() {
        let slots = Wire.slotIndices(for: Geometry(keyCount: 12, knobCount: 2))
        #expect(Array(slots.prefix(12)) == Array(1...12))
        #expect(Array(slots.suffix(6)) == [16, 17, 18, 19, 20, 21])
    }

    @Test("Records round-trip through decode")
    func roundTrip() throws {
        for text in ["ctrl+shift+a", "cmd+c, cmd+v", "media:playpause",
                     "mouse:right", "mouse:wheelup", "ctrl+mouse:wheeldown",
                     "f13", "none"] {
            let action = try KeyAction.parse(text)
            let rec = Packet.record(keyIndex: 1, layer: 0, action: action)
            #expect(Packet.decode(record: rec) == action, "round trip failed for \(text)")
        }
    }

    @Test("Geometry is read from response bytes 2 and 3")
    func geometryDecode() {
        var response = [UInt8](repeating: 0, count: 64)
        response[2] = 6   // keys
        response[3] = 2   // knobs
        let geo = Packet.decodeGeometry(response)
        #expect(geo == Geometry(keyCount: 6, knobCount: 2))
        #expect(geo?.totalBindings == 12)   // 6 + 2*3
        #expect(geo?.describe == "6 keys + 2 knobs")
    }
}

@Suite("Action parsing")
struct ActionParsingTests {

    @Test("Chords accept Mac and PC modifier spellings")
    func modifierSpellings() throws {
        #expect(try KeyAction.parse("cmd+a") == KeyAction.parse("win+a"))
        #expect(try KeyAction.parse("alt+a") == KeyAction.parse("option+a"))
        #expect(try KeyAction.parse("ctrl+a") == KeyAction.parse("control+a"))
    }

    @Test("Right-hand modifiers use the high nibble")
    func rightHandModifiers() throws {
        guard case .keyboard(let chords) = try KeyAction.parse("rshift+a") else {
            Issue.record("expected a keyboard action"); return
        }
        #expect(chords[0].modifiers == .rightShift)
        #expect(chords[0].modifiers.rawValue == 0b0010_0000)
    }

    @Test("Unknown names are rejected with a useful message")
    func rejectsUnknown() {
        #expect(throws: ActionParseError.self) { try KeyAction.parse("ctrl+nope") }
        #expect(throws: ActionParseError.self) { try KeyAction.parse("media:nope") }
        #expect(throws: ActionParseError.self) { try KeyAction.parse("mouse:nope") }
    }

    @Test("Over-long macros are rejected rather than silently truncated")
    func rejectsLongMacro() {
        let long = Array(repeating: "a", count: 19).joined(separator: ", ")
        #expect(throws: ActionParseError.self) { try KeyAction.parse(long) }
    }

    @Test("Display names round-trip back through the parser")
    func displayRoundTrip() throws {
        for text in ["ctrl+shift+a", "cmd+c, cmd+v", "media:mute", "mouse:middle", "f24"] {
            let action = try KeyAction.parse(text)
            #expect(try KeyAction.parse(action.displayName) == action)
        }
    }
}

@Suite("Profiles")
struct ProfileTests {

    @Test("Profiles serialise to readable JSON and round-trip")
    func jsonRoundTrip() throws {
        var profile = Profile(name: "Test", geometry: Geometry(keyCount: 6, knobCount: 2))
        profile.set(try KeyAction.parse("ctrl+shift+a"), key: 1, layer: 0)
        profile.set(try KeyAction.parse("media:volumeup"), key: 7, layer: 0)

        let json = try profile.jsonString()
        #expect(json.contains("\"ctrl+shift+a\""))   // readable, not a tagged blob
        #expect(json.contains("\"media:volumeup\""))

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        #expect(decoded == profile)
    }

    @Test("Setting an action to none removes the assignment")
    func clearingRemoves() throws {
        var profile = Profile()
        profile.set(try KeyAction.parse("a"), key: 1, layer: 0)
        #expect(profile.assignments.count == 1)
        profile.set(.none, key: 1, layer: 0)
        #expect(profile.assignments.isEmpty)
    }
}

@Suite("Backlight")
struct LedTests {

    /// `SetRgb_Led_Key` writes 0xFE 0xB0 into slot 0 of the layer.
    @Test("LED record header is FE B0 <layer>")
    func header() {
        let rec = Packet.ledRecord(LedSetting(mode: 3, color: 2), layer: 1)
        #expect(rec[0] == 0xFE)
        #expect(rec[1] == 0xB0)
        #expect(rec[2] == 2)          // layer is 1-based on the wire
        #expect(rec[9] == 1)
        #expect(rec[11] == 0x23)      // colour 2 high nibble, mode 3 low
    }

    @Test("Mode and colour pack into one byte")
    func packing() {
        #expect(LedSetting(mode: 0, color: 5).packed == 0x50)
        #expect(LedSetting(mode: 5, color: 7).packed == 0x75)
        #expect(LedSetting(mode: 1, color: 1).packed == 0x11)
    }

    @Test("Packed bytes round-trip")
    func roundTrip() {
        for mode in LedSetting.modeRange {
            for color in LedSetting.colorRange {
                let s = LedSetting(mode: mode, color: color)
                #expect(LedSetting(packed: s.packed) == s)
            }
        }
    }

    /// The original forces colour 5 rather than letting the high nibble be zero.
    @Test("Colour zero becomes 5")
    func colourZeroDefaults() {
        #expect(LedSetting(mode: 2, color: 0).color == 5)
        #expect(LedSetting(packed: 0x02).color == 5)
    }

    @Test("Out-of-range values are clamped")
    func clamping() {
        #expect(LedSetting(mode: 99, color: 99).mode == 5)
        #expect(LedSetting(mode: 99, color: 99).color == 7)
    }

    @Test("Profiles carry backlight per layer and stay backward compatible")
    func profileLed() throws {
        var p = Profile(name: "T")
        p.setLed(LedSetting(mode: 2, color: 3), layer: 0)
        let json = try p.jsonString()
        let back = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(back.led(layer: 0) == LedSetting(mode: 2, color: 3))
        #expect(back.led(layer: 1) == nil)

        // A profile written before backlight support still loads.
        let old = #"{"name":"Old","assignments":[]}"#
        let decoded = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        #expect(decoded.leds.isEmpty)
    }

    @Test("apply sends the backlight record before the layer's keys")
    func applyOrder() throws {
        let mock = MockTransport()
        let pad = MacroPad(transport: mock)
        var p = Profile()
        p.set(try KeyAction.parse("a"), key: 1, layer: 0)
        p.setLed(LedSetting(mode: 1, color: 4), layer: 0)
        try pad.apply(p)

        #expect(mock.payloads[0][0] == 0xFE)   // backlight first
        #expect(mock.payloads[1][0] == 0xFD)   // then the key
        #expect(mock.payloads[2].prefix(3).elementsEqual([0xFD, 0xFE, 0xFF]))
    }
}
