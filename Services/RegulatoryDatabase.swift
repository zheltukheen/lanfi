import Foundation

struct RegulatoryChannel: Hashable {
    let channel: Int
    let isDFS: Bool
}

enum RegulatoryDatabase {
    private static let database: [String: [Rule]] = load()

    struct Rule {
        let low: Int
        let high: Int
        let isDFS: Bool
    }

    static func channels(countryCode: String?, band: WiFiBand) -> [RegulatoryChannel] {
        guard let countryCode, !countryCode.isEmpty else { return [] }
        let key = countryCode.uppercased()
        let rules = database[key] ?? database["00"] ?? []
        guard !rules.isEmpty else { return [] }
        let candidates: [Int]
        switch band {
        case .band24: candidates = Array(1...14)
        case .band5: candidates = Array(stride(from: 36, through: 165, by: 4))
        case .band6: candidates = Array(stride(from: 1, through: 233, by: 4))
        case .unknown: return []
        }
        return candidates.compactMap { channel in
            let frequency: Int
            switch band {
            case .band24: frequency = channel == 14 ? 2484 : 2407 + channel * 5
            case .band5: frequency = 5000 + channel * 5
            case .band6: frequency = 5950 + channel * 5
            case .unknown: return nil
            }
            guard let rule = rules.first(where: { frequency >= $0.low && frequency <= $0.high }) else { return nil }
            return RegulatoryChannel(channel: channel, isDFS: rule.isDFS)
        }
    }

    private static func load() -> [String: [Rule]] {
        guard let url = Bundle.main.url(forResource: "regulatory-db", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }
        var result: [String: [Rule]] = [:]
        var current: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("country ") {
                current = String(line.dropFirst("country ".count).prefix(2)).uppercased()
                if result[current!] == nil { result[current!] = [] }
            } else if let current, line.hasPrefix("(") {
                let parts = line.split(separator: "@", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let range = parts[0].replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let bounds = range.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard bounds.count == 2 else { continue }
                result[current, default: []].append(
                    Rule(low: bounds[0], high: bounds[1], isDFS: line.contains("DFS"))
                )
            }
        }
        return result
    }
}
