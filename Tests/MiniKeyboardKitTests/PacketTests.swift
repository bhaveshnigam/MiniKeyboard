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

    /// `read_Hidkey_Data`: movw $0xFA03 then arg bytes then the 1-based index.
    @Test("Read-key request is 03 FA <layer> <knobs> <index>")
    func readRequest() {
        let p = Packet.readKey(index: 7, layer: 2, knobCount: 3)
        #expect(Array(p[0..<5]) == [0x03, 0xFA, 0x02, 0x03, 0x07])
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

    @Test("Media and mouse modes set the mode byte")
    func modeBytes() throws {
        let media = Packet.record(keyIndex: 2, layer: 0,
                                  action: try KeyAction.parse("media:volumeup"))
        #expect(media[3] == 2)
        #expect(media[11] == 0x06)

        let mouse = Packet.record(keyIndex: 2, layer: 0,
                                  action: try KeyAction.parse("mouse:left"))
        #expect(mouse[3] == 3)
        #expect(mouse[10] == 0x01)

        let wheel = Packet.record(keyIndex: 2, layer: 0,
                                  action: try KeyAction.parse("mouse:wheeldown"))
        #expect(Int8(bitPattern: wheel[11]) == -1)
    }

    @Test("Records round-trip through decode")
    func roundTrip() throws {
        for text in ["ctrl+shift+a", "cmd+c, cmd+v", "media:playpause",
                     "mouse:right", "mouse:wheelup", "f13", "none"] {
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
