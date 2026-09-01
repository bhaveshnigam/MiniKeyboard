import Testing
import Foundation
@testable import MiniKeyboardKit

@Suite("Preset library")
struct PresetTests {

    /// The catalog is hand-written, so this is the guard that keeps a typo in a
    /// shortcut from shipping as a binding that silently does nothing.
    @Test("Every preset action parses")
    func allActionsParse() throws {
        for app in PresetLibrary.apps {
            for shortcut in app.shortcuts {
                #expect(throws: Never.self,
                        "\(app.name) / \(shortcut.label) -> \(shortcut.action)") {
                    try KeyAction.parse(shortcut.action)
                }
            }
        }
    }

    @Test("Every preset action survives a round trip to the wire and back")
    func allActionsRoundTrip() throws {
        for app in PresetLibrary.apps {
            for shortcut in app.shortcuts {
                let action = try KeyAction.parse(shortcut.action)
                let rec = Packet.record(keyIndex: 1, layer: 0, action: action)
                #expect(Packet.decode(record: rec) == action,
                        "\(app.name) / \(shortcut.label) did not survive encoding")
            }
        }
    }

    @Test("No preset binds nothing")
    func noEmptyBindings() throws {
        for app in PresetLibrary.apps {
            for shortcut in app.shortcuts {
                #expect(try KeyAction.parse(shortcut.action) != .none,
                        "\(app.name) / \(shortcut.label) parses to nothing")
            }
        }
    }

    @Test("App ids are unique and lookup works")
    func uniqueIDs() {
        let ids = PresetLibrary.apps.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(PresetLibrary.app(id: "zoom")?.name == "Zoom")
        #expect(PresetLibrary.app(id: "ZOOM")?.name == "Zoom")
        #expect(PresetLibrary.app(id: "nope") == nil)
    }

    @Test("Every app has shortcuts and a category")
    func wellFormed() {
        for app in PresetLibrary.apps {
            #expect(!app.shortcuts.isEmpty, "\(app.name) has no shortcuts")
            #expect(!app.category.isEmpty, "\(app.name) has no category")
            #expect(!app.name.isEmpty)
        }
        #expect(!PresetLibrary.categories.isEmpty)
    }

    @Test("Filling a layer assigns shortcuts to the pad's slots in order")
    func fillLayer() throws {
        let geo = Geometry(keyCount: 12, knobCount: 2)
        let profile = try Profile(filling: PresetLibrary.zoom, layer: 0, geometry: geo)

        // 12 keys plus 6 knob slots, capped by however many shortcuts exist.
        let expected = min(PresetLibrary.zoom.shortcuts.count, geo.totalBindings)
        #expect(profile.assignments.count == expected)

        // First key gets the first shortcut.
        let first = try KeyAction.parse(PresetLibrary.zoom.shortcuts[0].action)
        #expect(profile.action(key: 1, layer: 0) == first)

        // Knob slots start at 16, not right after key 12.
        #expect(profile.action(key: 13, layer: 0) == .none)
        #expect(profile.action(key: 16, layer: 0) != .none)
    }

    @Test("Filling respects the layer it is given")
    func fillLayerIndex() throws {
        let profile = try Profile(filling: PresetLibrary.slack, layer: 2,
                                  geometry: Geometry(keyCount: 6, knobCount: 0))
        #expect(profile.assignments.allSatisfy { $0.layer == 2 })
        #expect(profile.assignments.count == 6)
    }
}
