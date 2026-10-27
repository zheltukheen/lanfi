import Foundation

struct WorkspaceProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var filter: FilterProfile
    var columns: [ColumnDefinition]
    var coloringRules: [ColoringRule]
    var customFilters: [CustomFilter]
    var activeFilterId: String?
    var createdAt: Date

    static func new(
        name: String,
        filter: FilterProfile,
        columns: [ColumnDefinition],
        coloringRules: [ColoringRule],
        customFilters: [CustomFilter],
        activeFilterId: String?
    ) -> WorkspaceProfile {
        WorkspaceProfile(
            id: UUID(), name: name, filter: filter, columns: columns,
            coloringRules: coloringRules, customFilters: customFilters,
            activeFilterId: activeFilterId, createdAt: Date()
        )
    }
}

final class WorkspaceProfileStore {
    private let defaults: UserDefaults
    private let key = "LanFi.workspaceProfiles"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [WorkspaceProfile] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? decoder.decode([WorkspaceProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [WorkspaceProfile]) {
        guard let data = try? encoder.encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}
