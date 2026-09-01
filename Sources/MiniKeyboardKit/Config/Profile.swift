import Foundation

/// A full pad configuration, stored as readable JSON.
///
/// The original app had no persistence at all — the only copy of your layout
/// lived on the device. A profile is diffable and can live in a dotfiles repo.
public struct Profile: Codable, Sendable, Equatable {
    public struct Assignment: Codable, Sendable, Equatable {
        /// 1-based physical key index.
        public var key: Int
        /// 0-based layer.
        public var layer: Int
        public var action: KeyAction
        /// Inter-keystroke delay in milliseconds, for macros that need one.
        /// Absent means the firmware default.
        public var delay: Int?
        /// What the binding is for, in the application's own words — "Mute"
        /// rather than "shift+cmd+m". Presets supply it.
        ///
        /// The pad cannot store this, so it lives in the profile only. A layer
        /// read straight off the device comes back without labels.
        public var label: String?

        public init(key: Int, layer: Int, action: KeyAction,
                    delay: Int? = nil, label: String? = nil) {
            self.key = key
            self.layer = layer
            self.action = action
            self.delay = delay
            self.label = label
        }
    }

    /// Which preset a layer was filled from, so the UI can say whose shortcuts
    /// these are.
    public struct LayerSource: Codable, Sendable, Equatable {
        public var layer: Int
        /// Preset id, e.g. "teams".
        public var appID: String
        /// Display name, e.g. "Microsoft Teams".
        public var appName: String
        /// True when this was worked out from the bindings rather than set by
        /// filling the layer, so the UI can hedge instead of asserting.
        public var inferred: Bool

        public init(layer: Int, appID: String, appName: String, inferred: Bool = false) {
            self.layer = layer
            self.appID = appID
            self.appName = appName
            self.inferred = inferred
        }

        private enum CodingKeys: String, CodingKey { case layer, appID, appName, inferred }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            layer = try c.decode(Int.self, forKey: .layer)
            appID = try c.decode(String.self, forKey: .appID)
            appName = try c.decode(String.self, forKey: .appName)
            inferred = try c.decodeIfPresent(Bool.self, forKey: .inferred) ?? false
        }
    }

    /// Backlight for one layer.
    public struct LedAssignment: Codable, Sendable, Equatable {
        public var layer: Int
        public var mode: Int
        public var color: Int

        public init(layer: Int, setting: LedSetting) {
            self.layer = layer
            self.mode = setting.mode
            self.color = setting.color
        }
        public var setting: LedSetting { LedSetting(mode: mode, color: color) }
    }

    public var name: String
    public var geometry: Geometry?
    public var assignments: [Assignment]
    /// Per-layer backlight. Absent means "leave the pad's current setting".
    public var leds: [LedAssignment]
    /// Which preset filled each layer, where one did.
    public var layerSources: [LayerSource]

    public init(name: String = "Untitled",
                geometry: Geometry? = nil,
                assignments: [Assignment] = [],
                leds: [LedAssignment] = [],
                layerSources: [LayerSource] = []) {
        self.name = name
        self.geometry = geometry
        self.assignments = assignments
        self.leds = leds
        self.layerSources = layerSources
    }

    public func source(layer: Int) -> LayerSource? {
        layerSources.first { $0.layer == layer }
    }

    public mutating func setSource(_ source: LayerSource?, layer: Int) {
        layerSources.removeAll { $0.layer == layer }
        if let source {
            layerSources.append(source)
            layerSources.sort { $0.layer < $1.layer }
        }
    }

    public func label(key: Int, layer: Int) -> String? {
        assignments.first { $0.key == key && $0.layer == layer }?.label
    }

    /// Gives every layer its default colour, so the pad shows which one is live.
    public mutating func applyLayerColorCoding() {
        for layer in 0..<Wire.layerCount {
            setLed(LedSetting.defaultForLayer(layer), layer: layer)
        }
    }

    /// True when every layer already carries its default colour.
    public var isLayerColorCoded: Bool {
        (0..<Wire.layerCount).allSatisfy {
            led(layer: $0) == LedSetting.defaultForLayer($0)
        }
    }

    public func led(layer: Int) -> LedSetting? {
        leds.first { $0.layer == layer }?.setting
    }

    public mutating func setLed(_ setting: LedSetting?, layer: Int) {
        leds.removeAll { $0.layer == layer }
        if let setting {
            leds.append(LedAssignment(layer: layer, setting: setting))
            leds.sort { $0.layer < $1.layer }
        }
    }

    public func action(key: Int, layer: Int) -> KeyAction {
        assignments.first { $0.key == key && $0.layer == layer }?.action ?? .none
    }

    public func delay(key: Int, layer: Int) -> Int? {
        assignments.first { $0.key == key && $0.layer == layer }?.delay
    }

    public mutating func set(_ action: KeyAction, key: Int, layer: Int,
                             delay: Int? = nil, label: String? = nil) {
        if let i = assignments.firstIndex(where: { $0.key == key && $0.layer == layer }) {
            if action == .none {
                assignments.remove(at: i)
            } else {
                let changed = assignments[i].action != action
                assignments[i].action = action
                // Only overwrite the delay when one is supplied, so setting an
                // action does not silently discard a configured delay.
                if delay != nil { assignments[i].delay = delay }
                // A label describes a specific binding, so it must not outlive
                // it. Rebinding a key without supplying a new label clears it
                // rather than leaving "Mute" on something that no longer mutes.
                if let label {
                    assignments[i].label = label
                } else if changed {
                    assignments[i].label = nil
                }
            }
        } else if action != .none {
            assignments.append(Assignment(key: key, layer: layer, action: action,
                                          delay: delay, label: label))
        }
    }

    public mutating func setDelay(_ delay: Int?, key: Int, layer: Int) {
        guard let i = assignments.firstIndex(where: { $0.key == key && $0.layer == layer })
        else { return }
        assignments[i].delay = delay
    }

    // MARK: - JSON

    /// Actions round-trip through their textual form, so the JSON reads like
    /// `"action": "ctrl+shift+a"` rather than a tagged enum blob.
    private enum CodingKeys: String, CodingKey {
        case name, geometry, assignments, leds, layerSources
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        geometry = try c.decodeIfPresent(Geometry.self, forKey: .geometry)
        assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
        // Older profiles predate backlight and preset labelling.
        leds = try c.decodeIfPresent([LedAssignment].self, forKey: .leds) ?? []
        layerSources = try c.decodeIfPresent([LayerSource].self, forKey: .layerSources) ?? []
    }

    public static func load(from url: URL) throws -> Profile {
        try Profile.decoder.decode(Profile.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try Profile.encoder.encode(self).write(to: url, options: .atomic)
    }

    public func jsonString() throws -> String {
        String(decoding: try Profile.encoder.encode(self), as: UTF8.self)
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
    public static var decoder: JSONDecoder { JSONDecoder() }
}

// Encode `KeyAction` as its readable string form.
extension KeyAction {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do {
            self = try KeyAction.parse(text)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\(error)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayName)
    }
}

/// Turns Foundation's nested decoding errors into something a user can act on.
public func readableMessage(for error: any Error) -> String {
    guard let decoding = error as? DecodingError else {
        return "\(error)"
    }
    switch decoding {
    case .dataCorrupted(let context):
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        let where_ = path.isEmpty ? "" : " at \(path)"
        return context.debugDescription + where_
    case .keyNotFound(let key, _):
        return "missing required field \"\(key.stringValue)\""
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return "\(context.debugDescription) at \(path)"
    @unknown default:
        return "\(decoding)"
    }
}
