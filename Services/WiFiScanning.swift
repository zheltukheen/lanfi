import Foundation

/// The scan dependency the analyzer needs. `WiFiScanner` is the live CoreWLAN
/// implementation; tests and snapshots can inject a stub without a radio.
protocol WiFiScanning: Sendable {
    func scan() async throws -> [NetworkModel]
}

extension WiFiScanner: WiFiScanning {}
