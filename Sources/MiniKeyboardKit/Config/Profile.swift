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

        public init(key: Int, layer: Int, action: KeyAction) {
            self.key = key
            self.layer = layer
            self.action = action
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

    public init(name: String = "Untitled",
                geometry: Geometry? = nil,
                assignments: [Assignment] = [],
                leds: [LedAssignment] = []) {
        self.name = name
        self.geometry = geometry
        self.assignments = assignments
        self.leds = leds
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

    public mutating func set(_ action: KeyAction, key: Int, layer: Int) {
        if let i = assignments.firstIndex(where: { $0.key == key && $0.layer == layer }) {
            if action == .none {
                assignments.remove(at: i)
            } else {
                assignments[i].action = action
            }
        } else if action != .none {
            assignments.append(Assignment(key: key, layer: layer, action: action))
        }
    }

    // MARK: - JSON

    /// Actions round-trip through their textual form, so the JSON reads like
    /// `"action": "ctrl+shift+a"` rather than a tagged enum blob.
    private enum CodingKeys: String, CodingKey { case name, geometry, assignments, leds }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        geometry = try c.decodeIfPresent(Geometry.self, forKey: .geometry)
        assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
        // Older profiles predate backlight support.
        leds = try c.decodeIfPresent([LedAssignment].self, forKey: .leds) ?? []
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
