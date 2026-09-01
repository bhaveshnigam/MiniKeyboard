import Foundation
import Observation
import MiniKeyboardKit

/// One editable binding in the UI.
struct Binding: Identifiable, Hashable {
    enum Kind: Hashable {
        case key(Int)                  // 1-based physical key
        case knob(Int, Knob)           // 0-based knob index

        enum Knob: String, CaseIterable { case counterClockwise, press, clockwise }
    }
    var index: Int                     // wire index, 1-based
    var kind: Kind
    var id: Int { index }

    var label: String {
        switch kind {
        case .key(let n): return "\(n)"
        case .knob(let n, let dir):
            let arrow = switch dir {
            case .counterClockwise: "↺"
            case .press: "●"
            case .clockwise: "↻"
            }
            return "K\(n + 1)\(arrow)"
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .key(let n): return "Key \(n)"
        case .knob(let n, let dir):
            let d = switch dir {
            case .counterClockwise: "turn left"
            case .press: "press"
            case .clockwise: "turn right"
            }
            return "Knob \(n + 1) \(d)"
        }
    }
}

@Observable
@MainActor
final class AppModel {
    enum Status: Equatable {
        case disconnected
        case connected(Geometry)
        case error(String)
    }

    var status: Status = .disconnected
    var profile = Profile(name: "Untitled")
    var selectedLayer = 0
    var selection: Int?
    var busyMessage: String?
    var toast: String?

    private var pad: MacroPad?

    var geometry: Geometry? {
        if case .connected(let g) = status { return g }
        return nil
    }

    var isConnected: Bool { geometry != nil }

    /// Wire indices laid out as keys first, then three bindings per knob —
    /// the same order `Identify_KeyBoard_style` uses to build its layouts.
    var bindings: [Binding] {
        guard let geo = geometry else { return [] }
        var result: [Binding] = []
        var wire = 1
        for k in 0..<geo.keyCount {
            result.append(Binding(index: wire, kind: .key(k + 1)))
            wire += 1
        }
        for k in 0..<geo.knobCount {
            for dir in Binding.Kind.Knob.allCases {
                result.append(Binding(index: wire, kind: .knob(k, dir)))
                wire += 1
            }
        }
        return result
    }

    func action(for binding: Binding) -> KeyAction {
        profile.action(key: binding.index, layer: selectedLayer)
    }

    func setAction(_ action: KeyAction, for binding: Binding) {
        profile.set(action, key: binding.index, layer: selectedLayer)
    }

    // MARK: - Device

    func connect() {
        do {
            let pad = try MacroPad.connect()
            let geo = try pad.queryGeometry()
            self.pad = pad
            status = .connected(geo)
            profile.geometry = geo
            if selection == nil { selection = bindings.first?.index }
        } catch {
            pad = nil
            status = .error("\(error)")
        }
    }

    func disconnect() {
        pad?.close()
        pad = nil
        status = .disconnected
    }

    func readFromDevice() {
        guard let pad else { return }
        busyMessage = "Reading from device…"
        Task {
            defer { busyMessage = nil }
            do {
                var read = try pad.readProfile()
                read.name = profile.name
                profile = read
                toast = "Read \(read.assignments.count) binding(s) from the pad."
            } catch {
                status = .error("\(error)")
            }
        }
    }

    func apply() {
        guard let pad else { return }
        busyMessage = "Writing…"
        Task {
            defer { busyMessage = nil }
            do {
                try pad.apply(profile)
                toast = "Applied \(profile.assignments.count) binding(s)."
            } catch {
                status = .error("\(error)")
            }
        }
    }

    func clearAll() {
        guard let pad else { return }
        busyMessage = "Clearing…"
        Task {
            defer { busyMessage = nil }
            do {
                try pad.clearAll()
                profile.assignments.removeAll()
                toast = "Cleared every key on all \(Wire.layerCount) layers."
            } catch {
                status = .error("\(error)")
            }
        }
    }

    // MARK: - Files

    func load(from url: URL) {
        do {
            profile = try Profile.load(from: url)
            toast = "Loaded \(url.lastPathComponent)."
        } catch {
            status = .error("\(error)")
        }
    }

    func save(to url: URL) {
        do {
            try profile.save(to: url)
            toast = "Saved \(url.lastPathComponent)."
        } catch {
            status = .error("\(error)")
        }
    }
}
