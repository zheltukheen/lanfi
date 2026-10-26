import Foundation
import SwiftUI

@MainActor
final class InterfacesViewModel: ObservableObject {
    @Published private(set) var report: InterfacesReport = .empty
    @Published private(set) var isScanning = false
    @Published var autoRefresh = true
    @Published var errorMessage: String?

    var lastUpdatedText: String {
        guard report.generatedAt != .distantPast else { return "Not scanned yet" }
        return "Updated \(report.generatedAt.formatted(date: .omitted, time: .standard))"
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let snapshot = await Task.detached(priority: .utility) {
            SystemInterfaceScanner.scan()
        }.value
        report = snapshot
        errorMessage = snapshot.interfaces.isEmpty ? "No network interfaces reported by the system." : nil
    }

    func copyReport() {
        var lines = [
            "LanFi network interfaces",
            "Generated: \(report.generatedAt.formatted(date: .abbreviated, time: .standard))",
            "Primary: \(report.primaryInterface ?? "-")",
            "Router: \(report.router ?? "-")",
            "DNS: \(report.dnsServers.joined(separator: ", "))",
            "",
        ]
        for interface in report.interfaces {
            lines.append(
                "\(interface.bsdName) [\(interface.kind.title)] \(interface.statusLabel) · "
                    + "IPv4 \(interface.ipv4.map(\.address).joined(separator: ", ")) · "
                    + "IPv6 \(interface.ipv6.map(\.address).joined(separator: ", ")) · "
                    + "RX \(interface.rxLabel) TX \(interface.txLabel)"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
