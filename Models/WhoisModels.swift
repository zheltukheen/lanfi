import Foundation

struct WhoisEvent: Identifiable, Equatable, Sendable {
    let id: String
    let action: String
    let date: Date?

    init(action: String, date: Date?) {
        self.id = "\(action)-\(date?.timeIntervalSince1970 ?? 0)"
        self.action = action
        self.date = date
    }
}

struct WhoisReport: Equatable, Sendable {
    let query: String
    let objectType: String
    let name: String
    let handle: String?
    let registrar: String?
    let statuses: [String]
    let events: [WhoisEvent]
    let nameservers: [String]

    var registrationDate: Date? { date(for: "registration") }
    var expirationDate: Date? { date(for: "expiration") }
    var lastChangedDate: Date? { date(for: "last changed") ?? date(for: "last update") }

    private func date(for action: String) -> Date? {
        events.first { $0.action.localizedCaseInsensitiveContains(action) }?.date
    }
}

enum WhoisError: Error, Equatable, LocalizedError {
    case invalidTarget
    case httpStatus(Int)
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidTarget:
            return "Enter a domain or IP address."
        case .httpStatus(let status):
            return "RDAP returned HTTP \(status)."
        case .invalidResponse:
            return "RDAP returned an unexpected response."
        case .server(let message):
            return message
        }
    }
}
