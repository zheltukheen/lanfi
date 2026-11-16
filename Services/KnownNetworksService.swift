import CoreWLAN
import Foundation

/// Lists the Wi-Fi networks saved in System Settings.
///
/// `networksetup -listpreferredwirelessnetworks` is a documented, public utility
/// that prints names only — no passwords, no Keychain access, no private APIs.
struct KnownNetworksService {
    func preferredNetworks(interfaceName: String? = nil) -> [KnownNetwork] {
        let name = interfaceName ?? CWWiFiClient.shared().interface()?.interfaceName ?? "en0"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listpreferredwirelessnetworks", name]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        return KnownNetworksParser.parse(text).map(KnownNetwork.init(ssid:))
    }
}
