import Foundation

/// High-level driver: geometry query, read-back, and applying a profile.
///
/// The original app slept a full second on the UI thread after each layer.
/// Here the commit is simply awaited, so applying a profile is effectively instant.
public final class MacroPad {
    private let transport: Transport

    public private(set) var geometry: Geometry?

    public init(transport: Transport) {
        self.transport = transport
    }

    /// Opens the first connected pad.
    public static func connect() throws -> MacroPad {
        MacroPad(transport: try IOKitTransport.open())
    }

    /// Asks the device how many keys and knobs it has.
    @discardableResult
    public func queryGeometry(timeout: TimeInterval = 0.5) throws -> Geometry {
        try transport.write(Packet.queryGeometry())
        guard let response = try transport.read(timeout: timeout),
              let geo = Packet.decodeGeometry(response) else {
            throw DeviceError.badResponse
        }
        geometry = geo
        return geo
    }

    /// Reads back what is currently programmed on one key.
    public func readKey(index: Int, layer: Int,
                        timeout: TimeInterval = 0.2) throws -> KeyAction {
        try transport.write(Packet.readKey(index: UInt8(index),
                                           layer: UInt8(layer + 1),
                                           knobCount: UInt8(geometry?.knobCount ?? 0)))
        guard let response = try transport.read(timeout: timeout) else {
            throw DeviceError.badResponse
        }
        return Packet.decode(record: response)
    }

    /// Reads the entire current configuration into a profile.
    public func readProfile() throws -> Profile {
        let geo = try geometry ?? queryGeometry()
        var profile = Profile(geometry: geo)
        for layer in 0..<Wire.layerCount {
            for index in 1...max(geo.totalBindings, 1) {
                // A key the firmware does not know about simply reads back empty.
                let action = (try? readKey(index: index, layer: layer)) ?? .none
                if action != .none {
                    profile.set(action, key: index, layer: layer)
                }
            }
        }
        return profile
    }

    /// Writes a profile to the device.
    ///
    /// Mirrors `Widget::HID_write`: records are sent per layer, then a
    /// `FD FE FF` commit closes each layer that had any change.
    public func apply(_ profile: Profile,
                      progress: ((Int, Int) -> Void)? = nil) throws {
        let work = profile.assignments
        var done = 0
        for layer in 0..<Wire.layerCount {
            let inLayer = work.filter { $0.layer == layer }
            guard !inLayer.isEmpty else { continue }
            for assignment in inLayer.sorted(by: { $0.key < $1.key }) {
                try transport.write(Packet.programKey(keyIndex: UInt8(assignment.key),
                                                      layer: layer,
                                                      action: assignment.action))
                done += 1
                progress?(done, work.count)
            }
            try transport.write(Packet.commit())
        }
    }

    /// Clears every key on every layer.
    public func clearAll() throws {
        let count = geometry?.totalBindings ?? 16
        for layer in 0..<Wire.layerCount {
            for index in 1...count {
                try transport.write(Packet.programKey(keyIndex: UInt8(index),
                                                      layer: layer, action: .none))
            }
            try transport.write(Packet.commit())
        }
    }

    /// Reboots the pad into its firmware bootloader.
    ///
    /// Deliberately not reachable from normal UI flows: after this the device
    /// stops responding to configuration commands until it is reflashed or replugged.
    public func enterBootloader() throws {
        try transport.write(Packet.enterBootloader())
    }

    public func close() { transport.close() }
}
