import LanFiCore
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
    private static let overrideKey = AppSettingsKey.customOUIOverrides.rawValue

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

    // MARK: - Persisted index

    /// The packed index is rebuilt from the 1.7 MB text database on every
    /// launch, which costs ~120 ms of parsing before the first scan can show a
    /// vendor. The index is therefore cached as a binary file next to the
    /// database and reused while its fingerprint still matches.
    static var indexFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("LanFi/oui-index.bin")
    }

    static let indexMagic = Data("LFOI1".utf8)

    /// FNV-1a over the sorted database, so any change to a vendor name or a
    /// prefix invalidates the cached file.
    static func fingerprint(of database: [String: String]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for key in database.keys.sorted() {
            for byte in key.utf8 {
                hash = (hash ^ UInt64(byte)) &* prime
            }
            hash = (hash ^ 0x09) &* prime
            for byte in (database[key] ?? "").utf8 {
                hash = (hash ^ UInt64(byte)) &* prime
            }
            hash = (hash ^ 0x0A) &* prime
        }
        return hash
    }

    static func encodeIndex(_ index: [OUIKey: String], fingerprint: UInt64) -> Data {
        var data = indexMagic
        appendBytes(fingerprint, count: 8, to: &data)
        appendBytes(UInt64(index.count), count: 4, to: &data)
        for (key, vendor) in index.sorted(by: { $0.key.value < $1.key.value }) {
            data.append(UInt8(key.length))
            appendBytes(key.value, count: 8, to: &data)
            let name = Data(vendor.utf8)
            appendBytes(UInt64(name.count), count: 2, to: &data)
            data.append(name)
        }
        return data
    }

    static func decodeIndex(_ data: Data) -> (fingerprint: UInt64, index: [OUIKey: String])? {
        var reader = ByteReader(data: data)
        guard reader.take(indexMagic.count) == indexMagic,
            let fingerprint = reader.uint(8),
            let count = reader.uint(4),
            count <= 1_000_000
        else { return nil }
        var index: [OUIKey: String] = [:]
        index.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let length = reader.byte(), (6...9).contains(Int(length)),
                let value = reader.uint(8),
                let nameLength = reader.uint(2),
                let name = reader.take(Int(nameLength)),
                let vendor = String(data: name, encoding: .utf8),
                !vendor.isEmpty
            else { return nil }
            index[OUIKey(value: value, length: Int(length))] = vendor
        }
        guard reader.isAtEnd else { return nil }
        return (fingerprint, index)
    }

    private static func appendBytes(_ value: UInt64, count: Int, to data: inout Data) {
        for shift in stride(from: (count - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    private struct ByteReader {
        let data: Data
        private var offset = 0

        init(data: Data) { self.data = data }

        var isAtEnd: Bool { offset == data.count }

        mutating func byte() -> UInt8? {
            guard offset < data.count else { return nil }
            defer { offset += 1 }
            return data[data.startIndex + offset]
        }

        mutating func uint(_ count: Int) -> UInt64? {
            var value: UInt64 = 0
            for _ in 0..<count {
                guard let next = byte() else { return nil }
                value = value << 8 | UInt64(next)
            }
            return value
        }

        mutating func take(_ count: Int) -> Data? {
            guard count >= 0, offset + count <= data.count else { return nil }
            defer { offset += count }
            let start = data.index(data.startIndex, offsetBy: offset)
            return data[start..<data.index(start, offsetBy: count)]
        }
    }

    private static func loadPersistedIndex(fingerprint: UInt64) -> [OUIKey: String]? {
        guard let data = try? Data(contentsOf: indexFileURL),
            let decoded = decodeIndex(data),
            decoded.fingerprint == fingerprint
        else { return nil }
        return decoded.index
    }

    private static func persist(index: [OUIKey: String], fingerprint: UInt64) {
        let url = indexFileURL
        let payload = encodeIndex(index, fingerprint: fingerprint)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? payload.write(to: url, options: .atomic)
        }
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
        if let cachedIndex {
            cacheLock.unlock()
            return cachedIndex
        }
        let database = cached ?? loadDatabase()
        cached = database
        let fingerprint = fingerprint(of: database)
        let persisted = loadPersistedIndex(fingerprint: fingerprint)
        let index = persisted ?? packedIndex(from: database)
        cachedIndex = index
        cacheLock.unlock()

        // Rebuilding from text costs ~120 ms on a cold launch, so the first
        // run writes the binary copy for the next one.
        if persisted == nil {
            persist(index: index, fingerprint: fingerprint)
        }
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
