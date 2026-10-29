import Foundation

struct DiagnosticTool: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let category: String
    let description: String
    let candidates: [String]
    let arguments: [String]
    let installHint: String?

    var command: String { candidates.joined(separator: " / ") }
}

enum ToolCatalog {
    static let all: [DiagnosticTool] = [
        DiagnosticTool(
            id: "wdutil", title: "wdutil", icon: "wifi.diagnostic", category: "Wi-Fi",
            description: "Apple Wi-Fi diagnostics: RSSI, noise, rate and channel.",
            candidates: ["/usr/bin/wdutil"], arguments: ["info"],
            installHint: nil
        ),
        DiagnosticTool(
            id: "networkQuality", title: "networkQuality", icon: "speedometer", category: "Network",
            description: "Apple network quality: download, upload, latency and responsiveness.",
            candidates: ["/usr/bin/networkQuality"], arguments: ["-v"],
            installHint: nil
        ),
        DiagnosticTool(
            id: "ping", title: "ping", icon: "dot.radiowaves.left.and.right", category: "Network",
            description: "Latency, jitter and loss to a host.",
            candidates: ["/sbin/ping"], arguments: ["-c", "10", "1.1.1.1"],
            installHint: nil
        ),
        DiagnosticTool(
            id: "traceroute", title: "traceroute", icon: "point.3.connected.trianglepath.dotted", category: "Network",
            description: "Path and per-hop latency to a host.",
            candidates: ["/usr/sbin/traceroute"], arguments: ["-m", "20", "1.1.1.1"],
            installHint: nil
        ),
        DiagnosticTool(
            id: "mtr", title: "mtr", icon: "chart.line.uptrend.xyaxis", category: "Network",
            description: "Combined ping/traceroute with loss and jitter per hop.",
            candidates: ["/usr/local/bin/mtr", "/opt/homebrew/bin/mtr"], arguments: ["-rwc", "10", "1.1.1.1"],
            installHint: "brew install mtr"
        ),
        DiagnosticTool(
            id: "dig", title: "dig", icon: "globe", category: "DNS",
            description: "DNS query time, answer and resolver status.",
            candidates: ["/usr/bin/dig"], arguments: ["+stats", "example.com"],
            installHint: nil
        ),
        DiagnosticTool(
            id: "dscacheutil", title: "dscacheutil", icon: "server.rack", category: "DNS",
            description: "macOS Directory Service cache lookup.",
            candidates: ["/usr/bin/dscacheutil"], arguments: ["-q", "host", "-a", "name", "example.com"],
            installHint: nil
        ),
        DiagnosticTool(
            id: "arp", title: "arp -a", icon: "desktopcomputer", category: "LAN",
            description: "Neighbour table: local IP and MAC addresses.",
            candidates: ["/usr/sbin/arp"], arguments: ["-a"],
            installHint: nil
        ),
        DiagnosticTool(
            id: "nmap", title: "nmap", icon: "network", category: "LAN",
            description: "LAN discovery and open-port scan.",
            candidates: ["/usr/local/bin/nmap", "/opt/homebrew/bin/nmap"], arguments: ["-sn", "192.168.1.0/24"],
            installHint: "brew install nmap"
        ),
        DiagnosticTool(
            id: "blueutil", title: "blueutil", icon: "antenna.radiowaves.left.and.right", category: "Wireless",
            description: "Bluetooth radio state and coexistence inspection.",
            candidates: ["/usr/local/bin/blueutil", "/opt/homebrew/bin/blueutil"], arguments: ["-p"],
            installHint: "brew install blueutil"
        ),
        DiagnosticTool(
            id: "airport", title: "airport -I", icon: "airplane", category: "Wi-Fi",
            description: "Legacy Apple80211 information for older macOS.",
            candidates: [
                "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport",
                "/usr/local/bin/airport",
            ],
            arguments: ["-I"],
            installHint: "Legacy airport utility is unavailable on this macOS; use wdutil."
        ),
        DiagnosticTool(
            id: "captive", title: "Captive portal check", icon: "lock.shield", category: "Security",
            description: "Detect captive portal/authentication interception.",
            candidates: ["/usr/bin/curl"],
            arguments: [
                "-sS", "-m", "10", "-o", "/dev/null", "-w", "%{http_code} %{url_effective}\\n",
                "http://captive.apple.com/hotspot-detect.html",
            ],
            installHint: nil
        ),
        DiagnosticTool(
            id: "iperf3", title: "iperf3", icon: "arrow.up.arrow.down", category: "Throughput",
            description: "Throughput to your own iperf3 server.",
            candidates: ["/usr/local/bin/iperf3", "/opt/homebrew/bin/iperf3"], arguments: ["-c", "192.168.1.10"],
            installHint: "brew install iperf3"
        ),
        DiagnosticTool(
            id: "hostapd_cli", title: "hostapd_cli", icon: "antenna.radiowaves.left.and.right", category: "AP",
            description: "Query hostapd on a local/remote AP (run locally or via SSH).",
            candidates: ["/usr/local/bin/hostapd_cli", "/opt/homebrew/bin/hostapd_cli"], arguments: ["all_sta"],
            installHint: "hostapd_cli is normally on the AP, not the Mac."
        ),
        DiagnosticTool(
            id: "iw_ssh", title: "iw phy via SSH", icon: "antenna.radiowaves.left.and.right", category: "RF",
            description: "Read a remote Linux/OpenWrt AP's supported channels and DFS flags.",
            candidates: ["/usr/bin/ssh"], arguments: ["user@openwrt.local", "iw", "phy"],
            installHint: "Replace user@host; key-based SSH required."
        ),
        DiagnosticTool(
            id: "hostapd_ssh", title: "hostapd_cli via SSH", icon: "person.3", category: "AP",
            description: "Read associated stations from a remote hostapd AP.",
            candidates: ["/usr/bin/ssh"], arguments: ["user@openwrt.local", "hostapd_cli", "all_sta"],
            installHint: "Replace user@host; hostapd_cli must be installed on the AP."
        ),
        DiagnosticTool(
            id: "custom", title: "Custom command", icon: "terminal", category: "Advanced",
            description: "Run a local executable with arguments (no shell).",
            candidates: ["/usr/bin/env"], arguments: ["iw", "phy"],
            installHint: nil
        ),
    ]

    static func tool(id: String) -> DiagnosticTool? { all.first { $0.id == id } }
}

enum ToolRunner {
    static func locate(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(executable: String, arguments: [String], timeout: TimeInterval = 120) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "Failed to start: \(error.localizedDescription)")
                    return
                }
                let deadline = DispatchTime.now() + timeout
                while process.isRunning && DispatchTime.now() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if process.isRunning {
                    process.terminate()
                    continuation.resume(returning: "Timed out after \(Int(timeout))s.")
                    return
                }
                let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let text = [out, err].filter { !$0.isEmpty }.joined(separator: "\n--- stderr ---\n")
                continuation.resume(returning: text.isEmpty ? "(no output)" : text)
            }
        }
    }
}
