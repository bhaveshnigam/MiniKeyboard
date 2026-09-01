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

    /// Reads back every record the pad reports for one layer.
    ///
    /// The firmware answers a single request with a burst of reports, so this
    /// keeps reading until the device goes quiet rather than requesting each
    /// key individually.
    public func readLayer(_ layer: Int,
                          idleTimeout: TimeInterval = 0.25)
                          throws -> [Int: (action: KeyAction, delay: Int?)] {
        try transport.write(Packet.readLayer(layer))

        var result: [Int: (action: KeyAction, delay: Int?)] = [:]
        while let response = try transport.read(timeout: idleTimeout) {
            let rec = Packet.strip(response)
            // The record carries its own key index and layer, so trust those
            // rather than assuming the reply order.
            guard let index = Packet.keyIndex(of: rec) else { continue }
            if let l = Packet.layer(of: rec), l != layer { continue }
            let action = Packet.decode(record: rec)
            if action != .none {
                result[index] = (action, Packet.delay(ofResponse: rec))
            }
        }
        return result
    }

    /// Reads the entire current configuration into a profile.
    public func readProfile() throws -> Profile {
        let geo = try geometry ?? queryGeometry()
        var profile = Profile(geometry: geo)
        for layer in 0..<Wire.layerCount {
            for (index, entry) in try readLayer(layer) {
                profile.set(entry.action, key: index, layer: layer, delay: entry.delay)
            }
        }
        profile.assignments.sort { ($0.layer, $0.key) < ($1.layer, $1.key) }
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
            let led = profile.led(layer: layer)
            guard !inLayer.isEmpty || led != nil else { continue }
            // The backlight record occupies slot 0, so it goes out first.
            if let led {
                try transport.write(Packet.led(led, layer: layer))
            }
            for assignment in inLayer.sorted(by: { $0.key < $1.key }) {
                try transport.write(Packet.programKey(keyIndex: UInt8(assignment.key),
                                                      layer: layer,
                                                      action: assignment.action))
                // The delay is a separate record: a mode 5 patch sent with an
                // action in it stores the delay and drops the action.
                if let delay = assignment.delay, delay > 0 {
                    try transport.write(Packet.delayReport(keyIndex: UInt8(assignment.key),
                                                           layer: layer, delay: delay))
                }
                done += 1
                progress?(done, work.count)
            }
            try transport.write(Packet.commit())
        }
    }

    /// Sets the backlight for one layer and commits.
    public func setLed(_ setting: LedSetting, layer: Int) throws {
        try transport.write(Packet.led(setting, layer: layer))
        try transport.write(Packet.commit())
    }

    /// Gives each layer its default colour in one pass.
    public func applyLayerColorCoding() throws {
        for layer in 0..<Wire.layerCount {
            try setLed(LedSetting.defaultForLayer(layer), layer: layer)
        }
    }

    /// Clears every key on every layer.
    public func clearAll() throws {
        let geometry = self.geometry ?? Geometry(keyCount: Wire.keySlotCount, knobCount: 3)
        for layer in 0..<Wire.layerCount {
            for index in Wire.slotIndices(for: geometry) {
                try transport.write(Packet.programKey(keyIndex: UInt8(index),
                                                      layer: layer, action: .none))
            }
            try transport.write(Packet.commit())
        }
    }

    /// Tells the pad what model it is.
    ///
    /// Only for a pad that misreports its geometry. Passing a variant the
    /// hardware does not match makes it claim keys it does not have, so this is
    /// not reachable from the UI.
    public func setVariant(_ geometry: Geometry) throws {
        guard Packet.knownVariants.contains(geometry) else {
            throw DeviceError.unsupportedVariant(geometry)
        }
        try transport.write(Packet.setVariant(geometry))
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
