import Foundation

enum GenericScanImporter {
    static func load(_ url: URL) throws -> [NetworkModel] {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "csv" {
            return parseCSV(String(decoding: data, as: UTF8.self))
        }
        let object = try JSONSerialization.jsonObject(with: data)
        if let root = object as? [String: Any], let rows = root["networks"] as? [[String: Any]] {
            return rows.compactMap(parseJSONRow)
        }
        if let rows = object as? [[String: Any]] {
            return rows.compactMap(parseJSONRow)
        }
        throw NSError(
            domain: "LanFi.Import", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Expected a LanFi network export or a CSV with a header row."
            ])
    }

    static func parseCSV(_ text: String) -> [NetworkModel] {
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let headers = splitCSV(String(lines[0])).map { $0.lowercased() }
        func index(_ names: [String]) -> Int? {
            names.compactMap { name in headers.firstIndex(of: name) }.first
        }
        let ssid = index(["ssid", "network name", "network"])
        let bssid = index(["bssid", "mac", "mac address"])
        guard let ssid, let bssid else { return [] }
        let band = index(["band"])
        let channel = index(["channel", "ch"])
        let width = index(["width", "widthmhz"])
        let signal = index(["signal", "signal dbm", "rssi", "rssidbm"])
        let security = index(["security", "auth"])
        let vendor = index(["vendor", "manufacturer"])

        return lines.dropFirst().compactMap { line in
            let fields = splitCSV(String(line))
            guard fields.count > max(ssid, bssid) else { return nil }
            return make(
                ssid: fields[ssid],
                bssid: fields[bssid],
                band: band.flatMap { fields.indices.contains($0) ? fields[$0] : nil },
                channel: channel.flatMap { fields.indices.contains($0) ? Int(fields[$0]) : nil },
                width: width.flatMap { fields.indices.contains($0) ? Int(fields[$0]) : nil },
                signal: signal.flatMap { fields.indices.contains($0) ? Int(fields[$0]) : nil },
                security: security.flatMap { fields.indices.contains($0) ? fields[$0] : nil },
                vendor: vendor.flatMap { fields.indices.contains($0) ? fields[$0] : nil }
            )
        }
    }

    private static func parseJSONRow(_ row: [String: Any]) -> NetworkModel? {
        guard let ssid = row["ssid"] as? String, let bssid = row["bssid"] as? String else { return nil }
        return make(
            ssid: ssid,
            bssid: bssid,
            band: row["band"] as? String,
            channel: row["channel"] as? Int,
            width: (row["widthMHz"] as? Int) ?? (row["width"] as? Int),
            signal: (row["signalDbm"] as? Int) ?? (row["signal"] as? Int),
            security: row["security"] as? String,
            vendor: row["vendor"] as? String
        )
    }

    private static func make(
        ssid: String, bssid: String, band: String?, channel: Int?, width: Int?,
        signal: Int?, security: String?, vendor: String?
    ) -> NetworkModel {
        let parsedBand: WiFiBand
        switch (band ?? "").lowercased() {
        case "2.4ghz", "2.4", "2.4 ghz": parsedBand = .band24
        case "5ghz", "5", "5 ghz": parsedBand = .band5
        case "6ghz", "6", "6 ghz": parsedBand = .band6
        default: parsedBand = .unknown
        }
        return NetworkModel(
            summaryID: "\(bssid)-\(ssid)", bssid: bssid.uppercased(), ssid: ssid,
            band: parsedBand, channel: channel ?? 0, widthMHz: width ?? 0,
            security: security ?? "Unknown", signal: signal ?? -100,
            vendor: vendor ?? "-"
        )
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
