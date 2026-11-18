import Foundation

/// One neighbour advertised by the Reduced Neighbor Report (element 201).
///
/// RNR is how a 2.4/5 GHz beacon points a client at its 6 GHz BSS, so decoding
/// it turns "this SSID has a hidden 6 GHz radio" into a channel hint.
struct RNRNeighbor: Equatable, Identifiable {
    let operatingClass: Int
    let channel: Int
    let tbttOffset: Int?
    let bssid: String?
    let shortSSID: UInt32?
    let bssParameters: UInt8?
    let psd20MHz: Int?
    let mldParameters: String?

    var id: String {
        "\(operatingClass)-\(channel)-\(bssid ?? "ssid:\(shortSSID ?? 0)")"
    }

    /// 6 GHz operating classes start at 131 (20/40/80/160 MHz from 5950 MHz).
    var isSixGHz: Bool { (131...137).contains(operatingClass) }

    var bandLabel: String { isSixGHz ? "6 GHz" : "Other" }

    var summary: String {
        var parts = ["Class \(operatingClass)", "ch \(channel)"]
        if let bssid { parts.append(bssid) }
        if let psd20MHz { parts.append("PSD \(psd20MHz) dBm/MHz") }
        return parts.joined(separator: " · ")
    }
}

enum ReducedNeighborReport {
    /// Neighbor AP Information: TBTT header (2), operating class (1), channel
    /// (1), then `count` TBTT Information fields of `length` bytes each.
    static func parse(_ data: Data) -> [RNRNeighbor] {
        var neighbors: [RNRNeighbor] = []
        var index = 0
        while index + 4 <= data.count {
            let header = UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
            let count = Int((header >> 4) & 0x0F) + 1
            let length = Int((header >> 8) & 0xFF)
            let operatingClass = Int(data[index + 2])
            let channel = Int(data[index + 3])
            index += 4
            guard length > 0 else { break }
            for _ in 0..<count {
                guard index + length <= data.count else { return neighbors }
                if let neighbor = parseTBTT(
                    data.subdata(in: index..<(index + length)),
                    operatingClass: operatingClass,
                    channel: channel)
                {
                    neighbors.append(neighbor)
                }
                index += length
            }
        }
        return neighbors
    }

    private static func parseTBTT(
        _ entry: Data, operatingClass: Int, channel: Int
    ) -> RNRNeighbor? {
        guard !entry.isEmpty else { return nil }
        let length = entry.count
        var cursor = 0
        let offset = Int(entry[cursor])
        cursor += 1

        var bssid: String?
        if length >= 7, cursor + 6 <= length {
            bssid = (cursor..<(cursor + 6))
                .map { String(format: "%02X", entry[$0]) }
                .joined(separator: ":")
            cursor += 6
        }

        var shortSSID: UInt32?
        if length >= 11, cursor + 4 <= length {
            shortSSID =
                UInt32(entry[cursor]) | (UInt32(entry[cursor + 1]) << 8)
                | (UInt32(entry[cursor + 2]) << 16) | (UInt32(entry[cursor + 3]) << 24)
            cursor += 4
        }

        var bssParameters: UInt8?
        if length >= 12, cursor < length {
            bssParameters = entry[cursor]
            cursor += 1
        }

        var psd20MHz: Int?
        if length >= 13, cursor < length {
            psd20MHz = Int(Int8(bitPattern: entry[cursor]))
            cursor += 1
        }

        var mldParameters: String?
        if length >= 16, cursor + 3 <= length {
            let mldId = entry[cursor] & 0x3F
            let linkId = entry[cursor + 1] & 0x0F
            let changeCount = entry[cursor + 2]
            mldParameters = "AP MLD \(mldId) · link \(linkId) · change \(changeCount)"
        }

        return RNRNeighbor(
            operatingClass: operatingClass,
            channel: channel,
            tbttOffset: offset == 255 ? nil : offset,
            bssid: bssid,
            shortSSID: shortSSID,
            bssParameters: bssParameters,
            psd20MHz: psd20MHz,
            mldParameters: mldParameters
        )
    }
}
