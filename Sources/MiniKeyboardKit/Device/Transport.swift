import Foundation

/// Anything that can exchange raw HID reports with a pad.
///
/// The real implementation talks to IOKit; tests use an in-memory fake, which
/// is what keeps the protocol layer verifiable without hardware.
public protocol Transport: AnyObject {
    func write(_ report: [UInt8]) throws
    /// Reads one input report, or returns `nil` on timeout.
    func read(timeout: TimeInterval) throws -> [UInt8]?
    func close()
}

public enum DeviceError: Error, CustomStringConvertible {
    case notFound
    case openFailed(Int32)
    case writeFailed(Int32)
    case accessDenied
    case badResponse

    public var description: String {
        switch self {
        case .notFound:
            return """
                No supported macro pad found. Check that it is plugged in \
                (expected USB vendor 0x1189).
                """
        case .openFailed(let c):
            return "Could not open the device (IOKit error 0x\(String(c, radix: 16)))."
        case .writeFailed(let c):
            return "Write failed (IOKit error 0x\(String(c, radix: 16)))."
        case .accessDenied:
            return """
                Access denied by macOS. Grant Input Monitoring to this app in \
                System Settings > Privacy & Security > Input Monitoring.
                """
        case .badResponse:
            return "The device returned a response that could not be parsed."
        }
    }
}
