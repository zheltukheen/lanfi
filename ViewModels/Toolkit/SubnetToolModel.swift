import Foundation
import SwiftUI

// MARK: - Subnet

@MainActor
final class SubnetToolModel: ObservableObject {
    @Published var input = "192.168.1.0/24"
    @Published private(set) var result: SubnetInfo?
    @Published var errorMessage: String?

    func calculate() {
        if let subnet = SubnetCalculator.parse(input) {
            result = subnet
            errorMessage = nil
        } else {
            result = nil
            errorMessage =
                "Enter a valid IPv4 CIDR or address + netmask, for example 192.168.1.10/24."
        }
    }

    func useCurrentNetwork() {
        let report = SystemInterfaceScanner.scan()
        guard
            let interface = report.interfaces.first(where: \.isPrimary),
            let ipv4 = interface.ipv4.first,
            let prefix = ipv4.prefixLength
        else {
            errorMessage = "Could not determine this Mac's IPv4 network."
            return
        }
        input = "\(ipv4.address)/\(prefix)"
        calculate()
    }
}
