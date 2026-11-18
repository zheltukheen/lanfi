import Foundation

extension MCPToolkit {
    // MARK: - Shared encoding

    static func recordType(_ raw: String) -> DNSRecordType? {
        let upper = raw.uppercased()
        return DNSRecordType.allCases.first { $0.label.uppercased() == upper }
    }

    static func recordJSON(_ record: DNSRecord) -> [String: Any] {
        [
            "type": record.type.label,
            "name": record.name,
            "ttl": record.ttl,
            "priority": record.priority.map { $0 as Any } ?? NSNull(),
            "value": record.value,
        ]
    }
}

enum MCPToolArgumentError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}
