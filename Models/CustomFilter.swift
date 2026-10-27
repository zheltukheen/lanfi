import Foundation

enum NetworkFilterField: String, Codable, CaseIterable, Identifiable {
    case ssid, bssid, vendor, band, channel, width, security, mode, generation
    case signal, noise, snr, quality, clients, utilization, apName, country, hidden, connected

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ssid: return "SSID"
        case .bssid: return "BSSID"
        case .vendor: return "Vendor"
        case .band: return "Band"
        case .channel: return "Channel"
        case .width: return "Width"
        case .security: return "Security"
        case .mode: return "Mode"
        case .generation: return "Generation"
        case .signal: return "Signal"
        case .noise: return "Noise"
        case .snr: return "SNR"
        case .quality: return "Quality"
        case .clients: return "Clients"
        case .utilization: return "Utilization"
        case .apName: return "AP name"
        case .country: return "Country"
        case .hidden: return "Hidden"
        case .connected: return "Connected"
        }
    }
}

enum NetworkFilterOperator: String, Codable, CaseIterable, Identifiable {
    case equals, notEquals, contains, notContains, greaterThan, lessThan, matchesRegex

    var id: String { rawValue }
    var title: String {
        switch self {
        case .equals: return "equals"
        case .notEquals: return "not equals"
        case .contains: return "contains"
        case .notContains: return "not contains"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .matchesRegex: return "matches regex"
        }
    }
}

struct NetworkFilterRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var field: NetworkFilterField
    var op: NetworkFilterOperator
    var value: String
    var isEnabled: Bool = true
}

struct CustomFilter: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var matchAll: Bool
    var rules: [NetworkFilterRule]
    var isBuiltIn: Bool = false

    func matches(_ network: NetworkModel, metrics: NetworkMetrics?, connectedBSSID: String?) -> Bool {
        let active = rules.filter(\.isEnabled)
        guard !active.isEmpty else { return true }
        let results = active.map { rule in
            NetworkFilterEngine.evaluate(rule, network: network, metrics: metrics, connectedBSSID: connectedBSSID)
        }
        return matchAll ? results.allSatisfy { $0 } : results.contains(true)
    }
}

enum NetworkFilterEngine {
    static func evaluate(
        _ rule: NetworkFilterRule,
        network: NetworkModel,
        metrics: NetworkMetrics?,
        connectedBSSID: String?
    ) -> Bool {
        let text: String
        let number: Double?
        switch rule.field {
        case .ssid: text = network.displaySSID; number = nil
        case .bssid: text = network.bssid; number = nil
        case .vendor: text = network.vendor; number = nil
        case .band: text = network.band.label; number = nil
        case .channel: text = String(network.channel); number = Double(network.channel)
        case .width: text = network.channelWidthLabel; number = Double(network.channelWidthMHz)
        case .security: text = network.security; number = nil
        case .mode: text = network.mode; number = nil
        case .generation: text = network.generation.label; number = nil
        case .signal: text = String(network.signal); number = Double(network.signal)
        case .noise: text = network.noise.map(String.init) ?? ""; number = network.noise.map(Double.init)
        case .snr: text = network.snr.map(String.init) ?? ""; number = network.snr.map(Double.init)
        case .quality: text = String(metrics?.qualityScore ?? 0); number = metrics.map { Double($0.qualityScore) }
        case .clients: text = network.clients.map(String.init) ?? ""; number = network.clients.map(Double.init)
        case .utilization:
            text = network.channelUtilization.map(String.init) ?? ""
            number = network.channelUtilization.map(Double.init)
        case .apName: text = network.apName ?? ""; number = nil
        case .country: text = network.countryCode ?? ""; number = nil
        case .hidden:
            let hidden = network.ssid.isEmpty
            text = hidden ? "true" : "false"
            number = hidden ? 1 : 0
        case .connected:
            let connected = !network.bssid.isEmpty && network.bssid == connectedBSSID
            text = connected ? "true" : "false"
            number = connected ? 1 : 0
        }

        let expected = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rule.op {
        case .equals:
            if let expectedNumber = Double(expected), let number { return number == expectedNumber }
            return text.caseInsensitiveCompare(expected) == .orderedSame
        case .notEquals:
            if let expectedNumber = Double(expected), let number { return number != expectedNumber }
            return text.caseInsensitiveCompare(expected) != .orderedSame
        case .contains:
            return text.localizedCaseInsensitiveContains(expected)
        case .notContains:
            return !text.localizedCaseInsensitiveContains(expected)
        case .greaterThan:
            guard let expectedNumber = Double(expected), let number else { return false }
            return number > expectedNumber
        case .lessThan:
            guard let expectedNumber = Double(expected), let number else { return false }
            return number < expectedNumber
        case .matchesRegex:
            guard let regex = try? NSRegularExpression(pattern: expected, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
    }
}

extension CustomFilter {
    static let automatic: [CustomFilter] = [
        CustomFilter(
            id: "auto-open", name: "Open networks", matchAll: true,
            rules: [NetworkFilterRule(field: .security, op: .contains, value: "open")], isBuiltIn: true
        ),
        CustomFilter(
            id: "auto-weak", name: "Weak signal", matchAll: true,
            rules: [NetworkFilterRule(field: .signal, op: .lessThan, value: "-75")], isBuiltIn: true
        ),
        CustomFilter(
            id: "auto-6ghz", name: "6 GHz", matchAll: true,
            rules: [NetworkFilterRule(field: .band, op: .equals, value: "6GHz")], isBuiltIn: true
        ),
        CustomFilter(
            id: "auto-wifi7", name: "Wi-Fi 7", matchAll: true,
            rules: [NetworkFilterRule(field: .generation, op: .equals, value: "11be")], isBuiltIn: true
        ),
        CustomFilter(
            id: "auto-wpa3", name: "WPA3", matchAll: true,
            rules: [NetworkFilterRule(field: .security, op: .contains, value: "WPA3")], isBuiltIn: true
        ),
        CustomFilter(
            id: "auto-hidden", name: "Hidden SSID", matchAll: true,
            rules: [NetworkFilterRule(field: .hidden, op: .equals, value: "true")], isBuiltIn: true
        ),
    ]
}

final class CustomFilterStore {
    private let defaults: UserDefaults
    private let key = "LanFi.customFilters"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [CustomFilter] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CustomFilter].self, from: data)) ?? []
    }

    func save(_ filters: [CustomFilter]) {
        let custom = filters.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        defaults.set(data, forKey: key)
    }
}
