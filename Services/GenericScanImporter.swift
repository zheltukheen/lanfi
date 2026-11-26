import Foundation

/// G4b: a richer result than `[NetworkModel]` so the UI can name the columns it
/// could not map instead of silently dropping them.
struct ScanImportResult {
    let networks: [NetworkModel]
    /// Header names (CSV) or keys (JSON) that matched nothing LanFi can use.
    let unmappedColumns: [String]
}

enum GenericScanImporter {
    static func load(_ url: URL) throws -> [NetworkModel] {
        try loadDetailed(url).networks
    }

    static func loadDetailed(_ url: URL) throws -> ScanImportResult {
        try loadDetailed(data: Data(contentsOf: url), filename: url.lastPathComponent)
    }

    static func load(data: Data, filename: String) throws -> [NetworkModel] {
        try loadDetailed(data: data, filename: filename).networks
    }

    static func loadDetailed(data: Data, filename: String) throws -> ScanImportResult {
        if filename.lowercased().hasSuffix(".csv") {
            return parseCSVDetailed(String(decoding: data, as: UTF8.self))
        }
        let object = try JSONSerialization.jsonObject(with: data)
        if let root = object as? [String: Any], let rows = root["networks"] as? [[String: Any]] {
            return parseJSONRows(rows)
        }
        if let rows = object as? [[String: Any]] {
            return parseJSONRows(rows)
        }
        throw NSError(
            domain: "LanFi.Import", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Expected a LanFi network export or a CSV with a header row."
            ])
    }

    static func parseCSV(_ text: String) -> [NetworkModel] {
        parseCSVDetailed(text).networks
    }

    static func parseCSVDetailed(_ text: String) -> ScanImportResult {
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        guard lines.count > 1 else { return ScanImportResult(networks: [], unmappedColumns: []) }

        let rawHeaders = splitCSV(String(lines[0]))
        let headers = rawHeaders.map(normalize)
        let mapping = headerMapping(headers)
        guard let ssid = mapping[.ssid], let bssid = mapping[.bssid] else {
            return ScanImportResult(networks: [], unmappedColumns: rawHeaders)
        }

        let unmapped = rawHeaders.enumerated().compactMap { index, name in
            headers[index].isEmpty || mapping.values.contains(index) ? nil : name
        }

        func value(_ field: Field, _ fields: [String]) -> String? {
            guard let index = mapping[field], fields.indices.contains(index) else { return nil }
            return fields[index]
        }

        let networks = lines.dropFirst().compactMap { line -> NetworkModel? in
            let fields = splitCSV(String(line))
            guard fields.count > max(ssid, bssid) else { return nil }
            return make(
                ssid: fields[ssid],
                bssid: fields[bssid],
                band: value(.band, fields),
                channel: integer(value(.channel, fields)),
                frequency: number(value(.frequency, fields)),
                width: integer(value(.width, fields)),
                signal: integer(value(.signal, fields)),
                security: value(.security, fields),
                vendor: value(.vendor, fields)
            )
        }
        return ScanImportResult(networks: networks, unmappedColumns: unmapped)
    }

    private static func parseJSONRows(_ rows: [[String: Any]]) -> ScanImportResult {
        let parsed = rows.map { row in
            (
                row,
                make(
                    ssid: string(row, ["ssid", "networkName", "network_name", "name"]),
                    bssid: string(row, ["bssid", "mac", "macAddress", "mac_address"]),
                    band: string(row, ["band", "frequencyBand", "frequency_band"]),
                    channel: integer(row["channel"]) ?? integer(row["ch"]),
                    frequency: number(row["frequency"] ?? row["freq"] ?? row["frequencyMHz"]),
                    width: integer(row["widthMHz"] ?? row["width"] ?? row["channelWidth"]),
                    signal: integer(row["signalDbm"] ?? row["signal"] ?? row["rssi"]),
                    security: string(row, ["security", "auth", "encryption"]),
                    vendor: string(row, ["vendor", "manufacturer", "oui"])
                )
            )
        }
        let networks = parsed.compactMap { $0.1 }
        let known = Set([
            "ssid", "networkname", "network_name", "name", "bssid", "mac", "macaddress",
            "mac_address", "band", "frequencyband", "frequency_band", "channel", "ch",
            "frequency", "freq", "frequencymhz", "widthmhz", "width", "channelwidth", "signal",
            "signaldbm", "rssi", "security", "auth", "encryption", "vendor", "manufacturer", "oui",
        ])
        let unmapped =
            parsed.first.map { first in
                first.0.keys
                    .filter { !known.contains($0.lowercased()) }
                    .sorted()
            } ?? []
        return ScanImportResult(networks: networks, unmappedColumns: unmapped)
    }

    /// Aliases named by WiFi Explorer Pro's importer (AirPort Utility, Aruba
    /// Utilities, Analiti, Mobile Eye) plus the spellings the exporters in the
    /// wild actually use.
    private enum Field: CaseIterable {
        case ssid, bssid, band, channel, frequency, width, signal, security, vendor

        var aliases: [String] {
            switch self {
            case .ssid:
                return ["ssid", "essid", "network name", "network", "name", "wifi name"]
            case .bssid:
                return [
                    "bssid", "mac", "mac address", "ap mac", "ap bssid",
                    "basic service set identifier",
                ]
            case .band:
                return ["band", "frequency band", "freq band", "radio band"]
            case .channel:
                return ["channel", "ch", "channel number", "channel nr"]
            case .frequency:
                return ["frequency", "freq", "frequency mhz", "freq mhz", "center frequency"]
            case .width:
                return [
                    "width", "widthmhz", "width mhz", "channel width", "channelwidth", "bandwidth",
                    "bw",
                ]
            case .signal:
                return [
                    "signal", "signal dbm", "signal db", "signal strength", "signal level",
                    "rssi", "rssi dbm", "rssi db", "rssidbm", "rssidb", "dbm",
                ]
            case .security:
                return [
                    "security", "auth", "authentication", "encryption", "security type", "auth type",
                ]
            case .vendor:
                return ["vendor", "manufacturer", "oui", "vendor name"]
            }
        }
    }

    private static func headerMapping(_ headers: [String]) -> [Field: Int] {
        var mapping: [Field: Int] = [:]
        var used = Set<Int>()
        for field in Field.allCases {
            guard
                let index = headers.enumerated().first(where: { item in
                    !item.element.isEmpty && !used.contains(item.offset)
                        && field.aliases.contains(item.element)
                })?.offset
            else { continue }
            mapping[field] = index
            used.insert(index)
        }
        return mapping
    }

    private static func normalize(_ header: String) -> String {
        header
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func string(_ row: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = row[key] as? String { return value }
        }
        return nil
    }

    private static func number(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        var cleaned =
            raw
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        // "36 (5 GHz)", "80 MHz", "-52 dBm": take the leading number.
        while let first = cleaned.first, !first.isNumber, first != "-", first != "+" {
            cleaned.removeFirst()
        }
        guard
            let match = cleaned.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "-" })
                .first, let value = Double(match)
        else { return nil }
        return value
    }

    private static func integer(_ raw: String?) -> Int? {
        number(raw).map { Int($0.rounded()) }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let double as Double: return Int(double.rounded())
        case let string as String: return integer(string)
        default: return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let int as Int: return Double(int)
        case let double as Double: return double
        case let string as String: return number(string)
        default: return nil
        }
    }

    private static func make(
        ssid: String?, bssid: String?, band: String?, channel: Int?, frequency: Double?,
        width: Int?, signal: Int?, security: String?, vendor: String?
    ) -> NetworkModel? {
        guard let ssid, let bssid, !bssid.isEmpty else { return nil }
        let resolvedChannel = channel ?? channelValue(fromFrequencyMHz: frequency)
        let parsedBand = bandValue(from: band) ?? bandValue(fromFrequencyMHz: frequency)
        return NetworkModel(
            summaryID: "\(bssid)-\(ssid)", bssid: bssid.uppercased(), ssid: ssid,
            band: parsedBand, channel: resolvedChannel ?? 0, widthMHz: width ?? 0,
            security: security ?? "Unknown", signal: signal ?? -100,
            vendor: vendor ?? "-"
        )
    }

    private static func bandValue(from value: String?) -> WiFiBand? {
        guard let value else { return nil }
        let normalized = normalize(value)
        switch normalized {
        case "2.4", "2.4ghz", "2.4 ghz", "2 ghz", "24": return .band24
        case "5", "5ghz", "5 ghz", "50": return .band5
        case "6", "6ghz", "6 ghz", "6e", "60": return .band6
        default: return nil
        }
    }

    private static func bandValue(fromFrequencyMHz frequency: Double?) -> WiFiBand {
        guard let frequency, frequency > 0 else { return .unknown }
        if frequency >= 5925 { return .band6 }
        if frequency >= 4900 { return .band5 }
        if frequency >= 2400 { return .band24 }
        return .unknown
    }

    private static func channelValue(fromFrequencyMHz frequency: Double?) -> Int? {
        guard let frequency, frequency > 0 else { return nil }
        if frequency == 2484 { return 14 }
        if frequency >= 5925 { return Int(((frequency - 5950) / 5).rounded()) }
        if frequency >= 4900 { return Int(((frequency - 5000) / 5).rounded()) }
        if frequency >= 2400 { return Int(((frequency - 2407) / 5).rounded()) }
        return nil
    }

    private static func splitCSV(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == "," && !quoted {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}
