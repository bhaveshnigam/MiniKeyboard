import Foundation
import Observation
import MiniKeyboardKit

/// One editable binding in the UI.
struct Binding: Identifiable, Hashable {
    enum Kind: Hashable {
        case key(Int)                  // 1-based physical key
        case knob(Int, Knob)           // 0-based knob index

        enum Knob: String, CaseIterable, Hashable {
            case counterClockwise, press, clockwise
        }
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

    /// The profile as it exists on the pad, so edits can be reported as unsaved.
    private var deviceProfile: Profile?

    /// True when the in-memory profile differs from what the pad holds.
    var hasUnsavedChanges: Bool {
        guard let deviceProfile else { return !profile.assignments.isEmpty }
        return normalized(profile) != normalized(deviceProfile)
    }

    private func normalized(_ p: Profile) -> [Profile.Assignment] {
        p.assignments.sorted { ($0.layer, $0.key) < ($1.layer, $1.key) }
    }

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
        for k in 0..<geo.keyCount {
            result.append(Binding(index: k + 1, kind: .key(k + 1)))
        }
        // Knob slots start at a fixed base, not right after the last key.
        for k in 0..<geo.knobCount {
            let base = Wire.knobSlotBase + k * Wire.slotsPerKnob
            for (offset, dir) in Binding.Kind.Knob.allCases.enumerated() {
                result.append(Binding(index: base + offset, kind: .knob(k, dir)))
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

    // MARK: - Presets

    /// Puts one shortcut on the selected key.
    func assign(_ shortcut: ShortcutPreset) {
        guard let index = selection,
              let binding = bindings.first(where: { $0.index == index }),
              let action = shortcut.parsed else { return }
        setAction(action, for: binding)
        toast = "\(binding.accessibilityLabel) -> \(action.displayLabel)"
    }

    /// Lays a whole preset across the current layer, keys first then knobs.
    func fillLayer(with preset: AppPreset) {
        guard let geo = geometry else { return }
        let slots = Wire.slotIndices(for: geo)
        for (slot, shortcut) in zip(slots, preset.shortcuts) {
            guard let action = shortcut.parsed else { continue }
            profile.set(action, key: slot, layer: selectedLayer)
        }
        let placed = min(slots.count, preset.shortcuts.count)
        let dropped = preset.shortcuts.count - placed
        toast = dropped > 0
            ? "Placed \(placed) \(preset.name) shortcuts; \(dropped) did not fit."
            : "Placed \(placed) \(preset.name) shortcuts on layer \(selectedLayer + 1)."
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
            // Show what is actually on the pad rather than an empty grid.
            readFromDevice()
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
                deviceProfile = read
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
                deviceProfile = profile
                toast = "Wrote \(profile.assignments.count) binding(s) to the pad."
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
                deviceProfile = profile
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
