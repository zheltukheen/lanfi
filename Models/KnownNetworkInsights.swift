import Foundation

/// Saved-network inventory enriched with the current scan. The saved list is
/// still names only; everything else is derived from what is visible now.
struct KnownNetworkRow: Identifiable, Equatable {
    let ssid: String
    let accessPoints: [NetworkModel]

    var id: String { ssid }

    var best: NetworkModel? {
        accessPoints.max { $0.signal < $1.signal }
    }

    var isInRange: Bool { best != nil }

    var bssidCount: Int {
        Set(accessPoints.map(\.bssid)).count
    }

    var channels: [Int] {
        Array(Set(accessPoints.map(\.channel))).sorted()
    }

    var channelLabel: String {
        guard let best else { return "—" }
        return "\(best.bandLabel) ch \(best.channel)"
    }

    var signalRangeLabel: String? {
        guard let best else { return nil }
        let weakest = accessPoints.map(\.signal).min() ?? best.signal
        return weakest == best.signal ? "\(best.signal) dBm" : "\(best.signal)…\(weakest) dBm"
    }

    var security: KnownNetworkSecurity {
        KnownNetworkSecurity(label: best?.security ?? "")
    }

    var generationLabel: String {
        best?.generationLabel ?? "—"
    }

    var widthMHz: Int? {
        guard let best, best.channelWidthMHz > 0 else { return nil }
        return best.channelWidthMHz
    }
}

/// Classification shared by the filter and the security warnings.
struct KnownNetworkSecurity: Equatable {
    let label: String

    private var lowercased: String { label.lowercased() }

    var isOpen: Bool { lowercased.contains("open") || lowercased.contains("none") }
    var isWEP: Bool { lowercased.contains("wep") }
    var isWPA3: Bool { lowercased.contains("wpa3") || lowercased.contains("owe") }
    var isWPA2: Bool { lowercased.contains("wpa2") }
    /// WPA without WPA2/3, or an unknown saved network.
    var isLegacy: Bool {
        guard !label.isEmpty else { return false }
        return lowercased.contains("wpa") && !isWPA2 && !isWPA3
    }

    var isInsecure: Bool { isOpen || isWEP || isLegacy }

    var summary: String {
        if label.isEmpty { return "—" }
        return label
    }
}

enum KnownNetworkFilter: String, CaseIterable, Identifiable {
    case all
    case inRange
    case outOfRange
    case insecure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All saved"
        case .inRange: return "In range"
        case .outOfRange: return "Not in range"
        case .insecure: return "Weak security"
        }
    }
}

enum KnownNetworkSort: String, CaseIterable, Identifiable {
    case name
    case signal
    case channel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .signal: return "Signal"
        case .channel: return "Channel"
        }
    }
}

struct KnownNetworksSummary: Equatable {
    var saved = 0
    var inRange = 0
    var outOfRange = 0
    var insecure = 0
    var unsavedVisible = 0

    var total: Int { saved }
}

enum KnownNetworksAnalysis {
    static func rows(saved: [KnownNetwork], visible: [NetworkModel]) -> [KnownNetworkRow] {
        var bySSID: [String: [NetworkModel]] = [:]
        for network in visible where !network.ssid.isEmpty {
            bySSID[network.ssid, default: []].append(network)
        }
        var seen = Set<String>()
        return saved.compactMap { saved in
            guard seen.insert(saved.ssid).inserted else { return nil }
            return KnownNetworkRow(ssid: saved.ssid, accessPoints: bySSID[saved.ssid] ?? [])
        }
    }

    static func filtered(
        _ rows: [KnownNetworkRow], filter: KnownNetworkFilter, sort: KnownNetworkSort
    ) -> [KnownNetworkRow] {
        let filtered = rows.filter { row in
            switch filter {
            case .all: return true
            case .inRange: return row.isInRange
            case .outOfRange: return !row.isInRange
            case .insecure: return row.security.isInsecure
            }
        }
        switch sort {
        case .name:
            return filtered.sorted {
                $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending
            }
        case .signal:
            return filtered.sorted {
                ($0.best?.signal ?? -120) > ($1.best?.signal ?? -120)
            }
        case .channel:
            return filtered.sorted {
                let left = $0.best
                let right = $1.best
                if left?.band != right?.band { return (left?.band.rawValue ?? -1) < (right?.band.rawValue ?? -1) }
                return (left?.channel ?? 0) < (right?.channel ?? 0)
            }
        }
    }

    static func summary(
        rows: [KnownNetworkRow], visible: [NetworkModel]
    ) -> KnownNetworksSummary {
        let savedNames = Set(rows.map(\.ssid))
        let unsavedNames = Set(
            visible.map(\.ssid).filter { !$0.isEmpty && !savedNames.contains($0) })
        return KnownNetworksSummary(
            saved: rows.count,
            inRange: rows.filter(\.isInRange).count,
            outOfRange: rows.filter { !$0.isInRange }.count,
            insecure: rows.filter { $0.security.isInsecure }.count,
            unsavedVisible: unsavedNames.count)
    }

    /// Visible networks not saved in System Settings, best AP per SSID.
    static func unsavedVisible(
        saved: [KnownNetwork], visible: [NetworkModel]
    ) -> [NetworkModel] {
        let savedNames = Set(saved.map(\.ssid))
        var best: [String: NetworkModel] = [:]
        for network in visible where !network.ssid.isEmpty && !savedNames.contains(network.ssid) {
            if let current = best[network.ssid], current.signal >= network.signal { continue }
            best[network.ssid] = network
        }
        return best.values.sorted { $0.signal > $1.signal }
    }

    /// One row per SSID, with the strongest BSSID's live values.
    static func csv(rows: [KnownNetworkRow]) -> String {
        var lines = [
            "ssid,bssid,signal_dbm,channel,band,width_mhz,security,generation,ap_count"
        ]
        for row in rows {
            let best = row.best
            lines.append(
                [
                    escape(row.ssid),
                    escape(best?.bssid ?? ""),
                    best.map { "\($0.signal)" } ?? "",
                    best.map { "\($0.channel)" } ?? "",
                    escape(best?.bandLabel ?? ""),
                    row.widthMHz.map(String.init) ?? "",
                    escape(row.security.summary),
                    escape(row.generationLabel),
                    "\(row.bssidCount)",
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func json(rows: [KnownNetworkRow]) -> Data {
        let objects: [[String: Any]] = rows.map { row in
            let best = row.best
            return [
                "ssid": row.ssid,
                "bssid": best?.bssid ?? "",
                "signalDBM": best?.signal ?? 0,
                "channel": best?.channel ?? 0,
                "band": best?.bandLabel ?? "",
                "widthMHz": row.widthMHz ?? 0,
                "security": row.security.summary,
                "generation": row.generationLabel,
                "accessPointCount": row.bssidCount,
            ]
        }
        return
            (try? JSONSerialization.data(
                withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
