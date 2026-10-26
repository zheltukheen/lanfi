import Foundation

/// Best-effort extraction of an access point name from vendor-specific
/// information elements. Vendors expose names in different ways; we only
/// accept plausible, quoted-free printable tokens and reject protocol terms.
enum APNameDetector {
    private static let rejected: Set<String> = [
        "WMM", "WPS", "WPA", "WPA2", "WPA3", "OWE", "PMF", "RSN", "SSID",
        "IEEE", "Wi-Fi", "WiFi", "802.11", "Qualcomm", "Microsoft", "Apple",
        "Cisco", "Aruba", "Ubiquiti", "TP-Link", "Ruckus", "Mist", "Huawei",
        "Vendor", "Specific", "Unknown", "Private", "Configured",
    ]

    static func name(
        for elements: [InformationElement],
        ssid: String,
        vendor: String
    ) -> String? {
        var candidates: [String] = []
        for element in elements
        where element.name.localizedCaseInsensitiveContains("Vendor Specific")
            || element.name.localizedCaseInsensitiveContains("Vendor")
        {
            candidates.append(contentsOf: printableStrings(in: element.rawHex))
        }

        let normalizedSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedVendor = vendor.lowercased()
        let filtered = candidates.filter { candidate in
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 4, value.count <= 48 else { return false }
            guard value.contains(where: { $0.isLetter }) else { return false }
            guard
                value.rangeOfCharacter(from: .decimalDigits) != nil
                    || value.contains("-")
                    || value.lowercased().hasPrefix("ap")
            else { return false }
            guard !rejected.contains(where: { value.caseInsensitiveCompare($0) == .orderedSame }) else {
                return false
            }
            guard !value.lowercased().contains("reserved") else { return false }
            if value.lowercased() == normalizedSSID && !normalizedSSID.isEmpty { return false }
            if value.lowercased().contains(normalizedVendor) && normalizedVendor != "-" { return false }
            guard value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{3,47}$"#, options: .regularExpression) != nil else {
                return false
            }
            return true
        }

        // Prefer hostname-like strings with a vendor/AP prefix, then shortest.
        return filtered.sorted { lhs, rhs in
            let left = lhs.lowercased()
            let right = rhs.lowercased()
            let leftBoost = left.hasPrefix("ap") || left.contains("ap-") || left.contains("-ap")
            let rightBoost = right.hasPrefix("ap") || right.contains("ap-") || right.contains("-ap")
            if leftBoost != rightBoost { return leftBoost }
            return lhs.count < rhs.count
        }.first
    }

    private static func printableStrings(in hex: String) -> [String] {
        let bytes =
            hex
            .split(whereSeparator: \.isWhitespace)
            .compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else { return [] }

        var strings: [String] = []
        var run: [UInt8] = []
        func flush() {
            guard run.count >= 3 else {
                run.removeAll(keepingCapacity: true)
                return
            }
            let value = String(decoding: run, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,;:()[]{}<> ").union(.whitespacesAndNewlines))
            if !value.isEmpty { strings.append(value) }
            run.removeAll(keepingCapacity: true)
        }

        for byte in bytes {
            if (32...126).contains(byte) {
                run.append(byte)
            } else {
                flush()
            }
        }
        flush()
        return strings
    }
}
