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
            for shortcut in app.shortcuts + app.knobs.flatMap(\.inOrder) {
                #expect(throws: Never.self,
                        "\(app.name) / \(shortcut.label) -> \(shortcut.action)") {
                    try KeyAction.parse(shortcut.action)
                }
            }
        }
    }

    @Test("Every app defines at least one knob")
    func knobsDefined() {
        for app in PresetLibrary.apps {
            #expect(!app.knobs.isEmpty, "\(app.name) has no knob definitions")
            for knob in app.knobs {
                #expect(!knob.name.isEmpty)
            }
        }
    }

    /// A turn has to be repeatable. Firing "Search" on every click of an
    /// encoder is the failure mode this guards against.
    @Test("Knob rotation is a repeatable action, not a one-shot command")
    func rotationIsContinuous() throws {
        // Actions that make sense to fire over and over as a knob turns.
        let repeatable: Set<String> = [
            "media:volumeup", "media:volumedown",
            "media:brightnessup", "media:brightnessdown",
            "media:next", "media:previous",
            "mouse:wheelup", "mouse:wheeldown",
            "mouse:scrollleft", "mouse:scrollright",
            "left", "right", "up", "down",
            "cmd+-", "cmd+=", "leftbracket", "rightbracket",
            "cmd+z", "shift+cmd+z",
            "shift+alt+up", "shift+alt+down",
            "ctrl+tab", "ctrl+shift+tab",
            "shift+cmd+leftbracket", "shift+cmd+rightbracket",
            "f1", "f2",
        ]
        for app in PresetLibrary.apps {
            for knob in app.knobs {
                for dir in [knob.counterClockwise, knob.clockwise] {
                    #expect(repeatable.contains(dir.action),
                            "\(app.name) / \(knob.name) rotation runs \(dir.action)")
                }
            }
        }
    }

    @Test("Every preset action survives a round trip to the wire and back")
    func allActionsRoundTrip() throws {
        for app in PresetLibrary.apps {
            for shortcut in app.shortcuts + app.knobs.flatMap(\.inOrder) {
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
            for shortcut in app.shortcuts + app.knobs.flatMap(\.inOrder) {
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

    @Test("Filling a layer puts keys on keys and knobs on knobs")
    func fillLayer() throws {
        let geo = Geometry(keyCount: 12, knobCount: 2)
        let zoom = PresetLibrary.zoom
        let profile = try Profile(filling: zoom, layer: 0, geometry: geo)

        // First key gets the first key shortcut.
        #expect(profile.action(key: 1, layer: 0)
                == (try KeyAction.parse(zoom.shortcuts[0].action)))

        // Knob slots start at 16, not right after key 12.
        #expect(profile.action(key: 13, layer: 0) == .none)

        // Knob 1 comes from the knob definitions, not the tail of the key list.
        let knob = zoom.knobs[0]
        #expect(profile.action(key: 16, layer: 0)
                == (try KeyAction.parse(knob.counterClockwise.action)))
        #expect(profile.action(key: 17, layer: 0)
                == (try KeyAction.parse(knob.press.action)))
        #expect(profile.action(key: 18, layer: 0)
                == (try KeyAction.parse(knob.clockwise.action)))
        #expect(profile.label(key: 16, layer: 0) == knob.counterClockwise.label)
    }

    @Test("A pad with no knobs gets none of the knob bindings")
    func noKnobs() throws {
        let profile = try Profile(filling: PresetLibrary.macOS, layer: 0,
                                  geometry: Geometry(keyCount: 6, knobCount: 0))
        #expect(profile.assignments.allSatisfy { $0.key <= 6 })
    }

    @Test("More keys than the preset defines leaves the rest empty")
    func fewerShortcutsThanKeys() throws {
        let profile = try Profile(filling: PresetLibrary.meet, layer: 0,
                                  geometry: Geometry(keyCount: 12, knobCount: 1))
        let keyCount = PresetLibrary.meet.shortcuts.count
        #expect(profile.action(key: keyCount, layer: 0) != .none)
        #expect(profile.action(key: keyCount + 1, layer: 0) == .none)
        #expect(profile.action(key: 16, layer: 0) != .none)   // knob still filled
    }

    @Test("Filling respects the layer it is given")
    func fillLayerIndex() throws {
        let profile = try Profile(filling: PresetLibrary.slack, layer: 2,
                                  geometry: Geometry(keyCount: 6, knobCount: 0))
        #expect(profile.assignments.allSatisfy { $0.layer == 2 })
        #expect(profile.assignments.count == 6)
    }

    @Test("Horizontal scroll round-trips as Shift plus wheel")
    func horizontalScroll() throws {
        let left = try KeyAction.parse("mouse:scrollleft")
        #expect(left == .mouse(modifiers: .leftShift, buttons: 0, wheel: -1))
        #expect(left.displayName == "mouse:scrollleft")
        #expect(left.displayLabel == "Scroll Left")
        #expect(try KeyAction.parse(left.displayName) == left)

        let rec = Packet.record(keyIndex: 1, layer: 0, action: left)
        #expect(Packet.decode(record: rec) == left)
    }
}

@Suite("Preset labelling")
struct PresetLabelTests {

    @Test("Filling a layer records the app and what each key is for")
    func fillRecordsProvenance() throws {
        let geo = Geometry(keyCount: 12, knobCount: 2)
        let profile = try Profile(filling: PresetLibrary.teams, layer: 1, geometry: geo)

        #expect(profile.source(layer: 1)?.appID == "teams")
        #expect(profile.source(layer: 1)?.appName == "Microsoft Teams")
        #expect(profile.source(layer: 0) == nil)

        // Key 1 carries Teams' own wording, not just the chord.
        let first = PresetLibrary.teams.shortcuts[0]
        #expect(profile.label(key: 1, layer: 1) == first.label)
        #expect(profile.action(key: 1, layer: 1) == (try KeyAction.parse(first.action)))
    }

    /// "Mute" must not survive onto a key that no longer mutes.
    @Test("Rebinding a key drops its label")
    func rebindingClearsLabel() throws {
        var p = Profile()
        p.set(try KeyAction.parse("shift+cmd+m"), key: 1, layer: 0, label: "Toggle mute")
        #expect(p.label(key: 1, layer: 0) == "Toggle mute")

        p.set(try KeyAction.parse("cmd+c"), key: 1, layer: 0)
        #expect(p.label(key: 1, layer: 0) == nil)
    }

    @Test("Re-setting the same action keeps the label")
    func sameActionKeepsLabel() throws {
        var p = Profile()
        p.set(try KeyAction.parse("cmd+c"), key: 1, layer: 0, label: "Copy")
        p.set(try KeyAction.parse("cmd+c"), key: 1, layer: 0)
        #expect(p.label(key: 1, layer: 0) == "Copy")
    }

    @Test("Labels and sources round-trip through JSON")
    func jsonRoundTrip() throws {
        let geo = Geometry(keyCount: 6, knobCount: 0)
        let p = try Profile(filling: PresetLibrary.zoom, layer: 0, geometry: geo)
        let back = try JSONDecoder().decode(
            Profile.self, from: Data(try p.jsonString().utf8))
        #expect(back.source(layer: 0)?.appName == "Zoom")
        #expect(back.label(key: 1, layer: 0) == PresetLibrary.zoom.shortcuts[0].label)
    }

    @Test("A profile written before labelling still loads")
    func backwardCompatible() throws {
        let old = #"{"name":"Old","assignments":[{"key":1,"layer":0,"action":"cmd+c"}]}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        #expect(p.layerSources.isEmpty)
        #expect(p.label(key: 1, layer: 0) == nil)
    }
}
