import CoreWLAN
import Foundation

/// Reads the machine identity and Wi-Fi interfaces that
/// `ScanModeCapabilities` needs. Kept out of the model so capability rules
/// stay testable without CoreWLAN.
enum ScanHardwareProbe {
    static func current() -> ScanHardwareProfile {
        ScanHardwareProfile(
            machineIdentifier: sysctl("hw.model"),
            cpuBrand: sysctl("machdep.cpu.brand_string"),
            interfaceNames: (CWWiFiClient.shared().interfaceNames() ?? []).sorted()
        )
    }

    private static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}
