import Foundation
import Observation
import MiniKeyboardKit

/// One editable binding in the UI.
struct PadBinding: Identifiable, Hashable {
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

/// Defaults key for the auto-save toggle. Free-standing because `@Observable`
/// cannot reference `Self` from a stored property's initializer.
let autoSaveDefaultsKey = "autoSaveEnabled"

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
    var confirmClearLayer = false

    /// Writes every change straight to the pad, the way lighting already does.
    /// On by default; the pad is the only place a layout lives, so leaving
    /// edits unwritten is the surprising behaviour, not the safe one.
    var autoSave: Bool = UserDefaults.standard.object(forKey: autoSaveDefaultsKey)
        as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoSave, forKey: autoSaveDefaultsKey)
            if autoSave && hasUnsavedChanges { scheduleAutoSave() }
        }
    }

    /// True while a debounced auto-save is pending or running.
    private(set) var isAutoSaving = false
    private var autoSaveTask: Task<Void, Never>?

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
    var bindings: [PadBinding] {
        guard let geo = geometry else { return [] }
        var result: [PadBinding] = []
        for k in 0..<geo.keyCount {
            result.append(PadBinding(index: k + 1, kind: .key(k + 1)))
        }
        // Knob slots start at a fixed base, not right after the last key.
        for k in 0..<geo.knobCount {
            let base = Wire.knobSlotBase + k * Wire.slotsPerKnob
            for (offset, dir) in PadBinding.Kind.Knob.allCases.enumerated() {
                result.append(PadBinding(index: base + offset, kind: .knob(k, dir)))
            }
        }
        return result
    }

    func action(for binding: PadBinding) -> KeyAction {
        profile.action(key: binding.index, layer: selectedLayer)
    }

    func setAction(_ action: KeyAction, for binding: PadBinding) {
        profile.set(action, key: binding.index, layer: selectedLayer)
        scheduleAutoSave()
    }

    /// Which preset filled a layer, where one did.
    func layerSource(_ layer: Int? = nil) -> Profile.LayerSource? {
        profile.source(layer: layer ?? selectedLayer)
    }

    /// What a binding is for, in the preset's own words.
    func purpose(for binding: PadBinding) -> String? {
        profile.label(key: binding.index, layer: selectedLayer)
    }

    /// Empties the current layer: every key and knob direction, plus any
    /// preset labelling. Other layers are untouched.
    func clearLayer() {
        profile.assignments.removeAll { $0.layer == selectedLayer }
        profile.setSource(nil, layer: selectedLayer)
        toast = "Cleared layer \(selectedLayer + 1)."
        scheduleAutoSave()
    }

    /// Drops the preset labelling from this layer, leaving the bindings alone.
    func clearLayerSource() {
        profile.setSource(nil, layer: selectedLayer)
        for i in profile.assignments.indices
        where profile.assignments[i].layer == selectedLayer {
            profile.assignments[i].label = nil
        }
        // Labels are local to the profile, so the pad needs no write here.
    }

    func delay(for binding: PadBinding) -> Int? {
        profile.delay(key: binding.index, layer: selectedLayer)
    }

    func setDelay(_ delay: Int?, for binding: PadBinding) {
        profile.setDelay(delay, key: binding.index, layer: selectedLayer)
        scheduleAutoSave()
    }

    // MARK: - Lighting

    /// Coalesces a burst of edits — filling a layer touches eighteen keys —
    /// into one write shortly after the user stops.
    func scheduleAutoSave() {
        guard autoSave, pad != nil else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.writeNow()
        }
    }

    /// Writes the profile to the pad, replacing what is there.
    private func writeNow() {
        guard let pad, hasUnsavedChanges else { return }
        isAutoSaving = true
        defer { isAutoSaving = false }
        do {
            try pad.apply(profile, clearingOmitted: true)
            deviceProfile = profile
            cacheProfile()
        } catch {
            status = .error("\(error)")
        }
    }

    /// Keeps the labelling this Mac knows about, since the pad cannot hold it.
    private func cacheProfile() {
        guard let pad else { return }
        ProfileStore.save(profile, vendorID: pad.vendorID,
                          productID: pad.productID, geometry: geometry)
    }

    /// Changes the effect, keeping the current colour.
    func setLed(mode: Int) {
        let current = profile.led(layer: selectedLayer)
        applyLed(LedSetting(mode: mode, color: current?.color ?? 5))
    }

    /// Changes the colour, keeping the current effect.
    func setLed(color: Int) {
        let current = profile.led(layer: selectedLayer)
        applyLed(LedSetting(mode: current?.mode ?? 1, color: color))
    }

    func clearLed() {
        profile.setLed(nil, layer: selectedLayer)
    }

    /// Gives every layer its own colour and writes all three straight away.
    func applyLayerColorCoding() {
        profile.applyLayerColorCoding()
        guard let pad else { return }
        do {
            try pad.applyLayerColorCoding()
            toast = "Layer 1 green, layer 2 blue, layer 3 red."
        } catch {
            status = .error("\(error)")
        }
    }

    /// Lighting is judged by looking at it, so write it to the pad immediately
    /// rather than waiting for the next Apply.
    private func applyLed(_ setting: LedSetting) {
        profile.setLed(setting, layer: selectedLayer)
        guard let pad else { return }
        do {
            try pad.setLed(setting, layer: selectedLayer)
        } catch {
            status = .error("\(error)")
        }
    }

    // MARK: - Presets

    /// Puts one shortcut on the selected key, keeping what it is for.
    func assign(_ shortcut: ShortcutPreset) {
        guard let index = selection,
              let binding = bindings.first(where: { $0.index == index }),
              let action = shortcut.parsed else { return }
        profile.set(action, key: binding.index, layer: selectedLayer,
                    label: shortcut.label)
        toast = "\(binding.accessibilityLabel) -> \(shortcut.label)"
        scheduleAutoSave()
    }

    /// Lays a whole preset across the current layer, keys first then knobs.
    func fillLayer(with preset: AppPreset) {
        guard let geo = geometry else { return }
        let slots = Wire.slotIndices(for: geo)
        for (slot, shortcut) in zip(slots, preset.shortcuts) {
            guard let action = shortcut.parsed else { continue }
            profile.set(action, key: slot, layer: selectedLayer, label: shortcut.label)
        }
        profile.setSource(Profile.LayerSource(layer: selectedLayer,
                                              appID: preset.id, appName: preset.name),
                          layer: selectedLayer)
        scheduleAutoSave()
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
            // Preset labelling cannot live on the pad, so bring back whatever
            // this Mac remembers about it before reading the bindings.
            if let cached = ProfileStore.load(vendorID: pad.vendorID,
                                              productID: pad.productID,
                                              geometry: geo) {
                profile = cached
            }
            // Then show what is actually on the pad rather than an empty grid.
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
                var read = try pad.readProfile(mergingLabelsFrom: profile)
                read.name = profile.name
                profile = read
                deviceProfile = read
                cacheProfile()
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
                try pad.apply(profile, clearingOmitted: true)
                deviceProfile = profile
                cacheProfile()
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
            scheduleAutoSave()
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
