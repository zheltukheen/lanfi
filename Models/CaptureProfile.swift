import Foundation

struct CaptureProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var interfaceName: String
    var duration: Int
    var monitorMode: Bool
    var filter: String

    static func new(
        name: String, interfaceName: String, duration: Int, monitorMode: Bool, filter: String
    ) -> CaptureProfile {
        CaptureProfile(
            id: UUID(), name: name, interfaceName: interfaceName,
            duration: duration, monitorMode: monitorMode, filter: filter
        )
    }
}

final class CaptureProfileStore {
    private let defaults: UserDefaults
    private let key = "LanFi.captureProfiles"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [CaptureProfile] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CaptureProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [CaptureProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}
