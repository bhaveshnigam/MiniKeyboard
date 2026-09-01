import Foundation
import IOKit
import IOKit.hid

/// A `Transport` backed by IOKit's `IOHIDManager`.
///
/// This replaces the bundled `libhidapi.dylib` from the original app. Using the
/// system framework directly means no third-party binary to keep architecture-current.
public final class IOKitTransport: Transport, @unchecked Sendable {
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "com.minikeyboard.hid")
    private var inputBuffer: [UInt8]

    /// Reports delivered by the input callback, oldest first.
    private var pending: [[UInt8]] = []
    private let pendingLock = NSCondition()
    private var isOpen = false

    public let vendorID: Int
    public let productID: Int
    public let productName: String

    /// Largest input report this interface can deliver.
    public let maxInputReportSize: Int

    private init(device: IOHIDDevice) throws {
        self.device = device
        let inputSize = IOKitTransport.intProperty(device, kIOHIDMaxInputReportSizeKey)
            ?? Wire.inputReportLength
        self.maxInputReportSize = inputSize
        self.inputBuffer = [UInt8](repeating: 0, count: max(inputSize, Wire.inputReportLength))
        self.vendorID = IOKitTransport.intProperty(device, kIOHIDVendorIDKey) ?? 0
        self.productID = IOKitTransport.intProperty(device, kIOHIDProductIDKey) ?? 0
        self.productName = IOKitTransport.stringProperty(device, kIOHIDProductKey) ?? "Macro Pad"

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPermitted || result == kIOReturnNotPrivileged {
                throw DeviceError.accessDenied
            }
            throw DeviceError.openFailed(result)
        }
        isOpen = true

        inputBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buf.baseAddress!,
                CFIndex(buf.count),
                { context, _, _, _, _, reportBuf, reportLen in
                    guard let context else { return }
                    let me = Unmanaged<IOKitTransport>
                        .fromOpaque(context).takeUnretainedValue()
                    let bytes = [UInt8](UnsafeBufferPointer(start: reportBuf,
                                                            count: Int(reportLen)))
                    me.enqueue(bytes)
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func enqueue(_ report: [UInt8]) {
        pendingLock.lock()
        pending.append(report)
        pendingLock.signal()
        pendingLock.unlock()
    }

    // MARK: - Discovery

    /// Every connected device matching the known VID/PID table.
    public static func discoverAll() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = Wire.productIDs.map { pid -> [String: Any] in
            [kIOHIDVendorIDKey: Wire.vendorID, kIOHIDProductIDKey: pid]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        // Sort for a stable order across runs.
        return set.sorted {
            (intProperty($0, kIOHIDLocationIDKey) ?? 0) < (intProperty($1, kIOHIDLocationIDKey) ?? 0)
        }
    }

    /// A matching HID interface, with the descriptor fields that decide
    /// which one carries the configuration protocol.
    public struct Interface {
        public let vendorID: Int
        public let productID: Int
        public let usagePage: Int
        public let usage: Int
        public let product: String
        public let maxInput: Int
        public let maxOutput: Int
        let device: IOHIDDevice

        public var isVendorDefined: Bool { usagePage >= 0xFF00 }

        public var describe: String {
            String(format: "%04X:%04X  usagePage 0x%04X usage %d  in %d out %d  %@%@",
                   vendorID, productID, usagePage, usage, maxInput, maxOutput,
                   product, isVendorDefined ? "  [config interface]" : "")
        }
    }

    /// Every matching interface, with descriptors.
    public static func interfaces() -> [Interface] {
        discoverAll().map { dev in
            Interface(
                vendorID: intProperty(dev, kIOHIDVendorIDKey) ?? 0,
                productID: intProperty(dev, kIOHIDProductIDKey) ?? 0,
                usagePage: intProperty(dev, kIOHIDPrimaryUsagePageKey) ?? 0,
                usage: intProperty(dev, kIOHIDPrimaryUsageKey) ?? 0,
                product: stringProperty(dev, kIOHIDProductKey) ?? "unknown",
                maxInput: intProperty(dev, kIOHIDMaxInputReportSizeKey) ?? 0,
                maxOutput: intProperty(dev, kIOHIDMaxOutputReportSizeKey) ?? 0,
                device: dev)
        }
    }

    /// Opens one specific interface.
    public static func open(_ interface: Interface) throws -> IOKitTransport {
        try IOKitTransport(device: interface.device)
    }

    /// Opens the pad's configuration interface.
    ///
    /// These pads expose several HID interfaces; only the vendor-defined one
    /// (usage page >= 0xFF00) accepts the 0x03 configuration reports. The
    /// others are the ordinary keyboard/consumer endpoints.
    public static func open() throws -> IOKitTransport {
        let devices = discoverAll()
        guard !devices.isEmpty else { throw DeviceError.notFound }

        let vendorInterfaces = devices.filter { dev in
            guard let page = intProperty(dev, kIOHIDPrimaryUsagePageKey) else { return false }
            return page >= 0xFF00
        }
        // Fall back to the last interface, which is where the config endpoint
        // sits on pads that do not report a vendor usage page.
        let candidates = vendorInterfaces.isEmpty ? [devices.last!] : vendorInterfaces

        var lastError: Error = DeviceError.notFound
        for dev in candidates {
            do { return try IOKitTransport(device: dev) } catch { lastError = error }
        }
        throw lastError
    }

    // MARK: - Transport

    public func write(_ report: [UInt8]) throws {
        guard isOpen else { throw DeviceError.writeFailed(kIOReturnNotOpen) }
        // This interface declares a 65-byte output report and the leading 0x03
        // is part of that report body, not a separate prefix. hidapi behaves the
        // same way: it only strips the first byte when it is zero. So the whole
        // buffer goes on the wire, with byte 0 doubling as the report ID.
        let reportID = CFIndex(report[0])
        let result = report.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID,
                                 buf.baseAddress!, buf.count)
        }
        guard result == kIOReturnSuccess else { throw DeviceError.writeFailed(result) }
    }

    public func read(timeout: TimeInterval) throws -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        pendingLock.lock()
        defer { pendingLock.unlock() }
        while pending.isEmpty {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            // The input callback is scheduled on the main run loop, so pump it
            // when we are the main thread and simply wait otherwise.
            if Thread.isMainThread {
                pendingLock.unlock()
                RunLoop.current.run(mode: .default,
                                    before: Date().addingTimeInterval(min(remaining, 0.01)))
                pendingLock.lock()
            } else if !pendingLock.wait(until: deadline) {
                return nil
            }
        }
        return pending.removeFirst()
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(),
                                         CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit { close() }

    // MARK: - Properties

    static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }
    static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}
