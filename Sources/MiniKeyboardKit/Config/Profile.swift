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

    public var name: String
    public var geometry: Geometry?
    public var assignments: [Assignment]

    public init(name: String = "Untitled",
                geometry: Geometry? = nil,
                assignments: [Assignment] = []) {
        self.name = name
        self.geometry = geometry
        self.assignments = assignments
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
    private enum CodingKeys: String, CodingKey { case name, geometry, assignments }

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
