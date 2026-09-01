import Foundation

/// How well a layer's bindings line up with a known preset.
public struct PresetMatch: Sendable, Equatable {
    public let presetID: String
    public let presetName: String
    /// Bindings on the layer that this preset also defines.
    public let matched: Int
    /// Bindings on the layer that carry any action at all.
    public let total: Int

    public var confidence: Double { total == 0 ? 0 : Double(matched) / Double(total) }
}

/// Works out which preset a layer probably came from, by what its keys do.
///
/// A layer read off the pad has no labels — the firmware cannot store them — so
/// when this Mac has no record of it, the bindings themselves are the only
/// evidence. Matching is order-independent: keys may have been moved around or
/// a few swapped out, and it should still recognise the set.
public enum PresetMatcher {

    /// Below this share of matching bindings, it is not a recognisable layout.
    public static let minimumConfidence = 0.5
    /// Common shortcuts overlap between apps, so a handful of hits proves
    /// nothing on its own.
    public static let minimumMatches = 3
    /// How far ahead the winner must be before naming it rather than guessing
    /// between two similar sets.
    public static let requiredMargin = 0.12

    /// Every action a preset defines, keys and knobs together.
    static func actions(of preset: AppPreset) -> [KeyAction: String] {
        var table: [KeyAction: String] = [:]
        for shortcut in preset.shortcuts + preset.knobs.flatMap(\.inOrder) {
            guard let action = shortcut.parsed else { continue }
            // First wins, so the key list takes precedence over the knobs.
            if table[action] == nil { table[action] = shortcut.label }
        }
        return table
    }

    public static func score(_ layer: [Int: KeyAction], against preset: AppPreset)
        -> PresetMatch {
        let table = actions(of: preset)
        let live = layer.values.filter { $0 != .none }
        let hits = live.filter { table[$0] != nil }.count
        return PresetMatch(presetID: preset.id, presetName: preset.name,
                           matched: hits, total: live.count)
    }

    /// The preset a layer most likely came from, or nil when nothing fits
    /// clearly enough to be worth claiming.
    public static func bestMatch(for layer: [Int: KeyAction],
                                 in presets: [AppPreset] = PresetLibrary.apps)
        -> PresetMatch? {
        let ranked = presets.map { score(layer, against: $0) }
            .filter { $0.matched >= minimumMatches && $0.confidence >= minimumConfidence }
            .sorted { ($0.confidence, $0.matched) > ($1.confidence, $1.matched) }

        guard let best = ranked.first else { return nil }
        // Two presets that fit equally well mean neither can be named honestly.
        if ranked.count > 1, best.confidence - ranked[1].confidence < requiredMargin,
           best.matched == ranked[1].matched {
            return nil
        }
        return best
    }

    /// Labels for whichever of a layer's keys the preset recognises.
    public static func labels(for layer: [Int: KeyAction], from preset: AppPreset)
        -> [Int: String] {
        let table = actions(of: preset)
        return layer.reduce(into: [:]) { result, entry in
            if let label = table[entry.value] { result[entry.key] = label }
        }
    }
}

extension Profile {
    /// Names any layer that looks like a known preset and labels the keys it
    /// recognises. Layers already carrying a source are left alone.
    public mutating func inferLayerSources() {
        for layer in 0..<Wire.layerCount where source(layer: layer) == nil {
            let actions = assignments
                .filter { $0.layer == layer }
                .reduce(into: [Int: KeyAction]()) { $0[$1.key] = $1.action }
            guard let match = PresetMatcher.bestMatch(for: actions),
                  let preset = PresetLibrary.app(id: match.presetID) else { continue }

            for (key, label) in PresetMatcher.labels(for: actions, from: preset) {
                if let i = assignments.firstIndex(where: { $0.key == key && $0.layer == layer }) {
                    assignments[i].label = label
                }
            }
            setSource(LayerSource(layer: layer, appID: preset.id,
                                  appName: preset.name, inferred: true), layer: layer)
        }
    }
}
