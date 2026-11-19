import LanFiCore
import Foundation
import SwiftUI

@MainActor
final class ToolkitViewModel: ObservableObject {
    @Published var selection: ToolboxTool = .overview {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: Self.selectionKey) }
    }

    private static let selectionKey = AppSettingsKey.toolkitSelection.rawValue

    let ping = PingToolModel()
    let dns = DNSToolModel()
    let dnsPropagation = DNSPropagationToolModel()
    let whois = WhoisToolModel()
    let geoIP = GeoIPToolModel()
    let portScan = PortScanToolModel()
    let traceroute = TracerouteToolModel()
    let mtr = MTRToolModel()
    let visualTraceroute = VisualTracerouteToolModel()
    let ssl = SSLToolModel()
    let subnet = SubnetToolModel()
    let pathCheck = PathCheckToolModel()
    let lanScanner = LANScannerToolModel()
    let iperf3 = Iperf3ToolModel()
    let speedTest = SpeedTestToolModel()
    let httpTraffic = HTTPTrafficToolModel()

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.selectionKey) {
            // 5.0.1 removed the duplicate "Wi-Fi Networks" item; it opened the
            // same screen as the analyzer, so old selections map onto it.
            let migrated = raw == "wifiNetworks" ? ToolboxTool.wifiAnalyzer.rawValue : raw
            if let stored = ToolboxTool(rawValue: migrated), stored.isAvailable {
                selection = stored
            }
        }
    }

    func select(_ tool: ToolboxTool) {
        guard tool.isAvailable else { return }
        selection = tool
    }
}
