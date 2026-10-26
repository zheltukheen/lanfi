import Foundation

enum OUIUpdater {
    static let remoteURL = URL(string: "https://www.wireshark.org/download/automated/data/manuf")!

    static var customDatabaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi/oui.txt")
    }

    static var lastUpdated: Date? {
        (try? FileManager.default.attributesOfItem(atPath: customDatabaseURL.path)[.modificationDate]) as? Date
    }

    static func update() async throws -> Date {
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 60
        request.setValue("LanFi/1.9 OUI updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            let text = String(data: data, encoding: .utf8)
        else {
            throw NSError(
                domain: "LanFi.OUI", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Vendor database download failed."
                ])
        }
        let database = parseManuf(text)
        guard database.count > 10_000 else {
            throw NSError(
                domain: "LanFi.OUI", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Vendor database response was unexpectedly small."
                ])
        }
        try FileManager.default.createDirectory(
            at: customDatabaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try database.mergingText().write(to: customDatabaseURL, atomically: true, encoding: .utf8)
        OUIParser.reload()
        return Date()
    }

    static func parseManuf(_ text: String) -> [String: String] {
        var database: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            if line.isEmpty || line.hasPrefix("#") { continue }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }
            let prefixPart = columns[0].split(separator: "/").first.map(String.init) ?? String(columns[0])
            let key = OUIParser.normalizedMAC(prefixPart)
            let vendor = columns.last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard (6...9).contains(key.count), !vendor.isEmpty else { continue }
            database[key] = vendor
        }
        return database
    }
}

private extension Dictionary where Key == String, Value == String {
    func mergingText() -> String {
        sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
    }
}
