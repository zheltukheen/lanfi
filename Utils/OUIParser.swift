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

    struct OUIKey: Hashable {
        let value: UInt64
        let length: Int
    }

    private static let cacheLock = NSLock()
    private static var cached: [String: String]?
    private static var cachedIndex: [OUIKey: String]?
    private static var cachedOverrides: [String: String]?
    private static let overrideKey = "LanFi.customOUIOverrides"

    /// Returns the best vendor name for a MAC address. The database contains
    /// 24-, 28- and 36-bit prefixes; the longest matching prefix wins.
    static func vendor(for bssid: String) -> String {
        let key = normalizedMAC(bssid)
        guard key.count >= 6 else { return "-" }

        if let firstByte = UInt8(key.prefix(2), radix: 16), firstByte & 0x02 != 0 {
            return "Randomized MAC"
        }

        if let custom = lookup(mac: key, in: customOverrides()) { return custom }
        return lookupPacked(mac: key, in: index()) ?? "-"
    }

    static func customOverrides() -> [String: String] {
        cacheLock.lock()
        if let cachedOverrides {
            cacheLock.unlock()
            return cachedOverrides
        }
        cacheLock.unlock()

        let decoded =
            UserDefaults.standard.data(forKey: overrideKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]

        cacheLock.lock()
        cachedOverrides = decoded
        cacheLock.unlock()
        return decoded
    }

    static func setOverride(prefix: String, vendor: String) -> Bool {
        let key = normalizedMAC(prefix)
        let value = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6...9).contains(key.count), !value.isEmpty else { return false }
        var overrides = customOverrides()
        overrides[key] = value
        guard let data = try? JSONEncoder().encode(overrides) else { return false }
        UserDefaults.standard.set(data, forKey: overrideKey)
        cacheLock.lock()
        cachedOverrides = overrides
        cacheLock.unlock()
        return true
    }

    static func removeOverride(_ prefix: String) {
        var overrides = customOverrides()
        overrides.removeValue(forKey: normalizedMAC(prefix))
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        UserDefaults.standard.set(data, forKey: overrideKey)
        cacheLock.lock()
        cachedOverrides = overrides
        cacheLock.unlock()
    }

    /// Warms both caches on a background task at launch so the first scan does
    /// not pay for parsing the 1.7 MB database.
    static func preload() {
        _ = customOverrides()
        _ = db()
        _ = index()
    }

    static func reload() {
        cacheLock.lock()
        cached = nil
        cachedIndex = nil
        cachedOverrides = nil
        cacheLock.unlock()
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

    /// Longest-prefix lookup over a packed database. Avoids four string
    /// allocations per BSSID on the hot scan path.
    static func lookupPacked(mac: String, in index: [OUIKey: String]) -> String? {
        let key = normalizedMAC(mac)
        guard key.count >= 6, let value = UInt64(key.prefix(12), radix: 16) else { return nil }
        for length in stride(from: min(9, key.count), through: 6, by: -1) {
            let shift = (12 - length) * 4
            let prefix = value >> UInt64(shift)
            if let vendor = index[OUIKey(value: prefix, length: length)], !vendor.isEmpty {
                return vendor
            }
        }
        return nil
    }

    /// Builds the integer-key index used by `lookupPacked`.
    static func packedIndex(from database: [String: String]) -> [OUIKey: String] {
        var index: [OUIKey: String] = [:]
        index.reserveCapacity(database.count)
        for (prefix, vendor) in database {
            guard (6...9).contains(prefix.count),
                let value = UInt64(prefix, radix: 16)
            else { continue }
            index[OUIKey(value: value, length: prefix.count)] = vendor
        }
        return index
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
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached { return cached }
        let database = loadDatabase()
        cached = database
        return database
    }

    private static func index() -> [OUIKey: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedIndex { return cachedIndex }
        let database = cached ?? loadDatabase()
        cached = database
        let index = packedIndex(from: database)
        cachedIndex = index
        return index
    }

    private static func loadDatabase() -> [String: String] {
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
