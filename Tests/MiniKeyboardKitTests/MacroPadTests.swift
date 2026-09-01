import Testing
import Foundation
@testable import MiniKeyboardKit

/// Records everything written and replays canned responses, so the driver's
/// packet sequencing can be asserted without a physical pad.
final class MockTransport: Transport, @unchecked Sendable {
    var written: [[UInt8]] = []
    var responses: [[UInt8]] = []
    var closed = false

    func write(_ report: [UInt8]) throws { written.append(report) }
    func read(timeout: TimeInterval) throws -> [UInt8]? {
        responses.isEmpty ? nil : responses.removeFirst()
    }
    func close() { closed = true }

    /// Payload bytes (report ID stripped) of each write.
    var payloads: [[UInt8]] { written.map { Array($0.dropFirst()) } }
}

@Suite("Driver sequencing")
struct MacroPadTests {

    private func geometryResponse(keys: Int, knobs: Int) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 64)
        r[2] = UInt8(keys); r[3] = UInt8(knobs)
        return r
    }

    @Test("queryGeometry sends the query and parses the reply")
    func query() throws {
        let mock = MockTransport()
        mock.responses = [geometryResponse(keys: 9, knobs: 3)]
        let pad = MacroPad(transport: mock)

        let geo = try pad.queryGeometry()
        #expect(geo == Geometry(keyCount: 9, knobCount: 3))
        #expect(mock.payloads.first?.prefix(3).elementsEqual([0xFB, 0xFB, 0xFB]) == true)
    }

    @Test("A missing reply surfaces as badResponse, not a hang")
    func queryTimeout() {
        let pad = MacroPad(transport: MockTransport())
        #expect(throws: DeviceError.self) { try pad.queryGeometry(timeout: 0.01) }
    }

    @Test("apply writes one record per assignment then commits each touched layer")
    func applySequencing() throws {
        let mock = MockTransport()
        let pad = MacroPad(transport: mock)

        var profile = Profile()
        profile.set(try KeyAction.parse("a"), key: 1, layer: 0)
        profile.set(try KeyAction.parse("b"), key: 2, layer: 0)
        profile.set(try KeyAction.parse("c"), key: 1, layer: 2)
        try pad.apply(profile)

        // 3 records + 1 commit for layer 0 + 1 commit for layer 2.
        #expect(mock.written.count == 5)

        let commits = mock.payloads.filter { $0.prefix(3).elementsEqual([0xFD, 0xFE, 0xFF]) }
        #expect(commits.count == 2, "one commit per layer that had changes")

        // Layer 1 was untouched, so nothing should reference it.
        let layerBytes = mock.payloads
            .filter { !$0.prefix(3).elementsEqual([0xFD, 0xFE, 0xFF]) }
            .map { $0[2] }
        #expect(Set(layerBytes) == [1, 3])   // wire layers are 1-based
    }

    @Test("apply reports progress for every record")
    func applyProgress() throws {
        let mock = MockTransport()
        let pad = MacroPad(transport: mock)
        var profile = Profile()
        for k in 1...4 { profile.set(try KeyAction.parse("a"), key: k, layer: 0) }

        var seen: [Int] = []
        try pad.apply(profile) { done, total in
            seen.append(done)
            #expect(total == 4)
        }
        #expect(seen == [1, 2, 3, 4])
    }

    @Test("Every report on the wire is exactly 65 bytes")
    func reportLengths() throws {
        let mock = MockTransport()
        let pad = MacroPad(transport: mock)
        var profile = Profile()
        profile.set(try KeyAction.parse("ctrl+c, ctrl+v"), key: 1, layer: 0)
        try pad.apply(profile)
        #expect(mock.written.allSatisfy { $0.count == 65 })
        #expect(mock.written.allSatisfy { $0[0] == 0x03 })
    }

    @Test("readLayer decodes a burst of records and keys them by index")
    func readBack() throws {
        let mock = MockTransport()
        func padded(_ r: [UInt8]) -> [UInt8] {
            r + [UInt8](repeating: 0, count: 65 - r.count)
        }
        mock.responses = [
            padded(Packet.record(keyIndex: 3, layer: 0,
                                 action: try KeyAction.parse("cmd+shift+4"))),
            padded(Packet.record(keyIndex: 7, layer: 0,
                                 action: try KeyAction.parse("media:mute"))),
            // A record for another layer must be ignored.
            padded(Packet.record(keyIndex: 1, layer: 2,
                                 action: try KeyAction.parse("a"))),
        ]

        let pad = MacroPad(transport: mock)
        let layer = try pad.readLayer(0)
        #expect(layer.count == 2)
        #expect(layer[3]?.action == (try KeyAction.parse("cmd+shift+4")))
        #expect(layer[7]?.action == (try KeyAction.parse("media:mute")))
        #expect(layer[1] == nil)
    }

    @Test("clearAll zeroes every binding on every layer")
    func clearAll() throws {
        let mock = MockTransport()
        mock.responses = [geometryResponse(keys: 3, knobs: 1)]
        let pad = MacroPad(transport: mock)
        try pad.queryGeometry()
        try pad.clearAll()

        let bindings = Wire.slotIndices(for: Geometry(keyCount: 3, knobCount: 1)).count
        #expect(bindings == 6)   // keys 1-3 plus knob slots 16-18
        // (bindings records + 1 commit) per layer, after the geometry query.
        #expect(mock.written.count == (bindings + 1) * Wire.layerCount + 1)

        let records = mock.payloads.dropFirst()   // skip the geometry query
            .filter { !$0.prefix(3).elementsEqual([0xFD, 0xFE, 0xFF]) }
        #expect(records.allSatisfy { $0[9] == 0 }, "step count must be zero when cleared")
    }
}
