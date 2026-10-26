import Foundation

enum NetworkGroupMode: String, CaseIterable, Identifiable, Codable {
    case none
    case ssid
    case band
    case vendor
    case security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .ssid: return "SSID"
        case .band: return "Band"
        case .vendor: return "Vendor"
        case .security: return "Security"
        }
    }
}

struct NetworkGroup: Identifiable, Equatable {
    let id: String
    let mode: NetworkGroupMode
    let value: String
    let networkCount: Int
    let bestSignal: Int
    let averageQuality: Int?
    let bands: [WiFiBand]

    var title: String {
        value.isEmpty ? "Unknown" : value
    }

    var subtitle: String {
        var parts = ["\(networkCount) network\(networkCount == 1 ? "" : "s")"]
        if bands.count > 1 {
            parts.append(bands.map(\.label).joined(separator: " + "))
        }
        parts.append("best \(bestSignal) dBm")
        if let averageQuality {
            parts.append("avg Q\(averageQuality)")
        }
        return parts.joined(separator: " · ")
    }
}

enum NetworkTableRow: Identifiable, Equatable {
    case group(NetworkGroup)
    case network(NetworkModel)

    var id: String {
        switch self {
        case .group(let group): return "group-\(group.id)"
        case .network(let network): return "network-\(network.id)"
        }
    }

    var network: NetworkModel? {
        if case .network(let network) = self { return network }
        return nil
    }
}

enum NetworkGrouper {
    static func rows(
        for networks: [NetworkModel],
        mode: NetworkGroupMode,
        metricsByNetworkId: [String: NetworkMetrics],
        annotationsByNetworkId: [String: NetworkAnnotation]
    ) -> [NetworkTableRow] {
        guard mode != .none else {
            return networks.map(NetworkTableRow.network)
        }

        let grouped = Dictionary(grouping: networks) { value in
            switch mode {
            case .none: return ""
            case .ssid: return value.displaySSID
            case .band: return value.band.label
            case .vendor: return value.vendor == "-" ? "Unknown vendor" : value.vendor
            case .security: return value.security
            }
        }

        let sortedKeys = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var rows: [NetworkTableRow] = []
        rows.reserveCapacity(networks.count + sortedKeys.count)

        for key in sortedKeys {
            guard let members = grouped[key], !members.isEmpty else { continue }
            let metrics = members.compactMap { metricsByNetworkId[$0.id] }
            let averageQuality =
                metrics.isEmpty
                ? nil
                : Int(round(Double(metrics.reduce(0) { $0 + $1.qualityScore }) / Double(metrics.count)))
            let bands = Array(Set(members.map(\.band))).sorted { $0.sortOrder < $1.sortOrder }
            let group = NetworkGroup(
                id: "\(mode.rawValue)-\(key)",
                mode: mode,
                value: key,
                networkCount: members.count,
                bestSignal: members.map(\.signal).max() ?? -100,
                averageQuality: averageQuality,
                bands: bands
            )
            rows.append(.group(group))
            rows.append(contentsOf: members.map(NetworkTableRow.network))
        }
        return rows
    }
}
