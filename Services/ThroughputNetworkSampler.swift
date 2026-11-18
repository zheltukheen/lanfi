import CoreWLAN
import Foundation

/// Reads the SSID/BSSID the Mac is associated with right before a speed test,
/// so history can be grouped per network. Names are only available when
/// Location Services is granted; without it the test is simply unattributed.
enum ThroughputNetworkSampler {
    static func current() -> SpeedTestNetwork? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let ssid = interface.ssid() ?? ""
        let bssid = interface.bssid()?.uppercased()
        guard !ssid.isEmpty || bssid != nil else { return nil }
        return SpeedTestNetwork(ssid: ssid, bssid: bssid)
    }
}
