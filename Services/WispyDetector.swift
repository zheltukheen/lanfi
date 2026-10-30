import Foundation
import IOKit
import IOKit.usb

/// Detects MetaGeek Wi-Spy spectrum analyzers attached to this Mac.
///
/// LanFi does not ship a user-space USB driver, so detection stops at the
/// I/O Registry: the app can report the model and point users at CSV
/// import for traces recorded with the vendor's Chanalyzer software.
enum WispyDetector {
    /// MetaGeek Instruments / Wi-Spy USB vendor ID.
    static let vendorID: UInt16 = 0x1781

    struct Device: Equatable {
        let productName: String
        let productID: UInt16
    }

    /// Wi-Spy devices currently present, without claiming any interface.
    static func connectedDevices() -> [Device] {
        var devices: [Device] = []
        let matching = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matching[kUSBVendorID] = NSNumber(value: vendorID)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let name =
                (IORegistryEntryCreateCFProperty(
                    service, "USB Product Name" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? String) ?? "Wi-Spy"
            let pid =
                (IORegistryEntryCreateCFProperty(
                    service, kUSBProductID as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? NSNumber)?.uint16Value ?? 0
            devices.append(Device(productName: name, productID: pid))
        }
        return devices
    }

    static var statusText: String {
        let devices = connectedDevices()
        if devices.isEmpty {
            return "No Wi-Spy device detected. Connect one over USB, or import a Chanalyzer CSV trace."
        }
        let names = devices.map(\.productName).joined(separator: ", ")
        return "Detected: \(names). Live USB reading is not bundled — "
            + "export a CSV trace from Chanalyzer and import it here."
    }
}
