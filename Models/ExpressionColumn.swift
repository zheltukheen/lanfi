import Foundation

struct ExpressionColumn: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var template: String
}

enum ExpressionEvaluator {
    static func evaluate(
        _ template: String, network: NetworkModel, metrics: NetworkMetrics?
    ) -> String {
        var result = template
        let values: [String: String] = [
            "ssid": network.displaySSID,
            "bssid": network.bssid,
            "vendor": network.vendor,
            "signal": String(network.signal),
            "noise": network.noise.map(String.init) ?? "—",
            "snr": network.snr.map(String.init) ?? "—",
            "channel": String(network.channel),
            "band": network.band.label,
            "width": network.channelWidthLabel,
            "security": network.security,
            "quality": String(metrics?.qualityScore ?? 0),
            "clients": network.clients.map(String.init) ?? "—",
            "utilization": network.channelUtilization.map { "\($0)%" } ?? "—",
            "generation": network.generation.label,
            "apname": network.apName ?? "—",
            "country": network.countryCode ?? "—",
        ]
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}

final class ExpressionColumnStore {
    private let defaults: UserDefaults
    private let key = "LanFi.expressionColumns"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [ExpressionColumn] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ExpressionColumn].self, from: data)) ?? []
    }

    func save(_ columns: [ExpressionColumn]) {
        guard let data = try? JSONEncoder().encode(columns) else { return }
        defaults.set(data, forKey: key)
    }
}
