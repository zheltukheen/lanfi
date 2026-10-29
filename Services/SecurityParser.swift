import Foundation

struct SecurityInfo: Equatable {
    let label: String
    let pmfRequired: Bool
    let akmSuites: [UInt32]
}

enum SecurityParser {
    /// Parses RSN (48) and WPA/vendor (221) information elements.
    static func parse(_ data: Data?) -> SecurityInfo? {
        guard let data, !data.isEmpty else { return nil }
        var offset = 0
        var rsn: SecurityInfo?
        var wpa: SecurityInfo?
        while offset + 2 <= data.count {
            let id = data[offset]
            let length = Int(data[offset + 1])
            offset += 2
            guard offset + length <= data.count else { break }
            let payload = data.subdata(in: offset..<(offset + length))
            if id == 48 {
                rsn = parseRSN(payload)
            } else if id == 221, payload.count >= 6,
                payload[0] == 0x00, payload[1] == 0x50, payload[2] == 0xF2
            {
                wpa = parseWPA(payload)
            }
            offset += length
        }
        return rsn ?? wpa
    }

    private static func parseRSN(_ data: Data) -> SecurityInfo? {
        guard data.count >= 2 else { return nil }
        var offset = 2  // version
        guard offset + 4 <= data.count else { return nil }
        offset += 4  // group cipher
        guard offset + 2 <= data.count else { return nil }
        let pairwiseCount = Int(read16(data, offset)); offset += 2
        guard offset + pairwiseCount * 4 <= data.count else { return nil }
        offset += pairwiseCount * 4
        guard offset + 2 <= data.count else { return nil }
        let akmCount = Int(read16(data, offset)); offset += 2
        var akms: [UInt32] = []
        for _ in 0..<akmCount {
            guard offset + 4 <= data.count else { break }
            let type = UInt32(data[offset + 3])
            akms.append(type)
            offset += 4
        }
        var pmfRequired = false
        if offset + 2 <= data.count {
            let capabilities = read16(data, offset)
            pmfRequired = capabilities & 0x0040 != 0
        }
        let hasSAE = akms.contains { $0 == 8 || $0 == 9 || $0 == 24 }
        let hasPSK = akms.contains(2)
        let hasEnterprise = akms.contains(1) || akms.contains(3) || akms.contains(5)
        let hasOWE = akms.contains(18)
        let label: String
        if hasOWE {
            label = "OWE"
        } else if hasSAE && hasPSK {
            label = "WPA3 Transition"
        } else if hasSAE {
            label = "WPA3 Personal"
        } else if hasEnterprise && pmfRequired {
            label = "WPA3 Enterprise"
        } else if hasEnterprise {
            label = "WPA2 Enterprise"
        } else if hasPSK {
            label = "WPA2 Personal"
        } else {
            label = "WPA2"
        }
        return SecurityInfo(label: label, pmfRequired: pmfRequired, akmSuites: akms)
    }

    private static func parseWPA(_ data: Data) -> SecurityInfo? {
        guard data.count >= 8 else { return nil }
        var offset = 6  // OUI + type
        guard offset + 4 <= data.count else { return nil }
        offset += 4  // group cipher
        guard offset + 2 <= data.count else { return nil }
        let pairwiseCount = Int(read16(data, offset)); offset += 2
        guard offset + pairwiseCount * 4 <= data.count else { return nil }
        offset += pairwiseCount * 4
        guard offset + 2 <= data.count else { return nil }
        let akmCount = Int(read16(data, offset)); offset += 2
        var akms: [UInt32] = []
        for _ in 0..<akmCount where offset + 4 <= data.count {
            akms.append(UInt32(data[offset + 3]))
            offset += 4
        }
        let label = akms.contains(1) ? "WPA Enterprise" : "WPA Personal"
        return SecurityInfo(label: label, pmfRequired: false, akmSuites: akms)
    }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 1 < data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
}
