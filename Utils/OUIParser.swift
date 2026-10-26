import Foundation

struct OUIParser {
    // Minimal fallback used only if the bundled database is missing.
    static let builtIn: [String: String] = [
        "000C29": "VMware, Inc.",
        "001B63": "Apple, Inc.",
        "001A2B": "Ayecom Technology Co., Ltd.",
        "001DD8": "Microsoft Corporation",
        "3C5AB4": "Google, Inc.",
        "44650D": "Amazon Technologies Inc.",
        "00095B": "NETGEAR",
        "F4F5D8": "Google, Inc.",
        "001E65": "Intel Corporate",
        "001310": "Cisco-Linksys, LLC",
        "FCFBFB": "Cisco Systems, Inc.",
        "D850E6": "ASUSTek COMPUTER INC.",
        "C0EEFB": "OnePlus Tech (Shenzhen) Ltd",
        "F82793": "Apple, Inc.",
        "00259C": "Cisco-Linksys, LLC",
        "002369": "Cisco-Linksys, LLC",
        "B827EB": "Raspberry Pi Foundation",
        "283737": "Apple, Inc.",
        "3C0754": "Apple, Inc.",
        "207693": "Lenovo (Beijing) Limited.",
    ]

    private static var cached: [String: String]?
    private static let overrideKey = "Wifa.customOUIOverrides"

    /// Returns the best vendor name for a MAC address. The database contains
    /// 24-, 28- and 36-bit prefixes; the longest matching prefix wins.
    static func vendor(for bssid: String) -> String {
        let key = normalizedMAC(bssid)
        guard key.count >= 6 else { return "-" }

        if let firstByte = UInt8(key.prefix(2), radix: 16), firstByte & 0x02 != 0 {
            return "Randomized MAC"
        }

        if let custom = lookup(mac: key, in: customOverrides()) { return custom }
        return lookup(mac: key, in: db()) ?? "-"
    }

    static func customOverrides() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: overrideKey),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    static func setOverride(prefix: String, vendor: String) -> Bool {
        let key = normalizedMAC(prefix)
        let value = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6...9).contains(key.count), !value.isEmpty else { return false }
        var overrides = customOverrides()
        overrides[key] = value
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: overrideKey)
        }
        return true
    }

    static func removeOverride(_ prefix: String) {
        var overrides = customOverrides()
        overrides.removeValue(forKey: normalizedMAC(prefix))
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: overrideKey)
        }
    }

    static func reload() {
        cached = nil
    }

    /// Longest-prefix lookup over a database of 6, 7, 8 or 9 hex characters.
    static func lookup(mac: String, in database: [String: String]) -> String? {
        let key = normalizedMAC(mac)
        guard key.count >= 6 else { return nil }
        for length in stride(from: min(9, key.count), through: 6, by: -1) {
            let prefix = String(key.prefix(length))
            if let vendor = database[prefix], !vendor.isEmpty {
                return vendor
            }
        }
        return nil
    }

    /// Parses the tab-separated database format: `<hex prefix>\t<vendor>`.
    /// Lines with malformed or too-short keys are ignored.
    static func parseDatabase(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = normalizedMAC(String(parts[0]))
            let vendor = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard (6...9).contains(key.count), !vendor.isEmpty else { continue }
            map[key] = vendor
        }
        return map
    }

    private static func db() -> [String: String] {
        if let cached { return cached }

        var database = builtIn
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let customURL = support.appendingPathComponent("LanFi/oui.txt")
        if let text = try? String(contentsOf: customURL, encoding: .utf8) {
            let parsed = parseDatabase(text)
            if !parsed.isEmpty { database = parsed }
        } else {
            let candidates: [(name: String, ext: String?)] = [("oui", nil), ("oui", "txt"), ("OUI", nil)]
            for candidate in candidates {
                if let url = Bundle.main.url(forResource: candidate.name, withExtension: candidate.ext),
                    let text = try? String(contentsOf: url, encoding: .utf8)
                {
                    let parsed = parseDatabase(text)
                    if !parsed.isEmpty { database = parsed; break }
                }
            }
        }
        cached = database
        return database
    }

    /// Normalizes MAC/OUI input to uppercase hex without separators. It does
    /// not truncate, so 28- and 36-bit prefixes remain usable.
    static func normalizedMAC(_ value: String) -> String {
        let stripped = value.uppercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.count >= 6, stripped.allSatisfy({ $0.isHexDigit }) else { return "" }
        return String(stripped.prefix(12))
    }
}
