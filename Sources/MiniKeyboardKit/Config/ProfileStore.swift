import Foundation

/// Remembers the last layout written to a pad, so preset labelling survives
/// quitting the app.
///
/// The firmware has nowhere to keep it. Every byte of a key record it does not
/// recognise is zeroed on write — spare bytes 6 to 8 and the tail past the
/// macro steps all read back as zero — so a template marker cannot live on the
/// device. It lives here instead, keyed by which pad it belongs to.
public enum ProfileStore {

    /// `~/Library/Application Support/MiniKeyboard`
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("MiniKeyboard", isDirectory: true)
    }

    /// One file per pad shape, so two different pads do not overwrite each
    /// other's labelling.
    public static func url(vendorID: Int, productID: Int, geometry: Geometry?) -> URL {
        let shape = geometry.map { "\($0.keyCount)x\($0.knobCount)" } ?? "unknown"
        let name = String(format: "last-%04X-%04X-%@.json", vendorID, productID, shape)
        return directory.appendingPathComponent(name)
    }

    public static func save(_ profile: Profile,
                            vendorID: Int, productID: Int, geometry: Geometry?) {
        let target = url(vendorID: vendorID, productID: productID, geometry: geometry)
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            try profile.save(to: target)
        } catch {
            // Losing the cache costs labels, not bindings, so it is not worth
            // interrupting the user over.
            NSLog("MiniKeyboard: could not cache profile: \(error)")
        }
    }

    public static func load(vendorID: Int, productID: Int,
                            geometry: Geometry?) -> Profile? {
        try? Profile.load(from: url(vendorID: vendorID, productID: productID,
                                    geometry: geometry))
    }

    public static func clear(vendorID: Int, productID: Int, geometry: Geometry?) {
        try? FileManager.default.removeItem(
            at: url(vendorID: vendorID, productID: productID, geometry: geometry))
    }
}
