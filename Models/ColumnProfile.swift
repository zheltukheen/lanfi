import Foundation

struct ColumnProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var columns: [ColumnDefinition]
    let createdAt: Date

    static func new(name: String, columns: [ColumnDefinition]) -> ColumnProfile {
        ColumnProfile(id: UUID(), name: name, columns: columns, createdAt: Date())
    }
}

final class ColumnProfileStore {
    private let defaults: UserDefaults
    private let key = "Wifa.columnProfiles"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .millisecondsSince1970
    }

    func profiles() -> [ColumnProfile] {
        guard let data = defaults.data(forKey: key) else { return [] }
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([ColumnProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [ColumnProfile]) {
        guard let data = try? encoder.encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}
