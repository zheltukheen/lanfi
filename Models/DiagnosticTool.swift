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

/// Specialised system tools that stay outside the Network Toolkit. General
/// network tools (ping, traceroute, DNS, ports, iperf3…) live in the toolkit
/// so there is one home and one parser for each.
enum ToolCatalog {
    static let all: [DiagnosticTool] = [
        DiagnosticTool(
            id: "wdutil", title: "wdutil", icon: "wifi.diagnostic", category: "Wi-Fi",
            description: "Apple Wi-Fi diagnostics: RSSI, noise, rate and channel.",
            candidates: ["/usr/bin/wdutil"], arguments: ["info"],
            installHint: nil
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
            id: "blueutil", title: "blueutil", icon: "antenna.radiowaves.left.and.right", category: "Wireless",
            description: "Bluetooth radio state and coexistence inspection.",
            candidates: ["/usr/local/bin/blueutil", "/opt/homebrew/bin/blueutil"], arguments: ["-p"],
            installHint: "brew install blueutil"
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
