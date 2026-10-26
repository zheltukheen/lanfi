import Foundation

struct RemoteSensor: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var username: String
    var port: Int
    var identityFile: String?

    static func new(name: String, host: String, username: String, port: Int = 22, identityFile: String? = nil)
        -> RemoteSensor
    {
        RemoteSensor(
            id: UUID(), name: name, host: host, username: username, port: port,
            identityFile: identityFile
        )
    }
}

struct RemoteNetwork: Identifiable, Equatable {
    let id: UUID
    let ssid: String
    let channel: Int
    let band: String
    let widthMHz: Int
    let phy: String
    let rssi: Int
    let noise: Int?
    let security: String

    var snr: Int? { noise.map { rssi - $0 } }
}

final class RemoteSensorStore {
    private let defaults: UserDefaults
    private let key = "Wifa.remoteSensors"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func sensors() -> [RemoteSensor] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RemoteSensor].self, from: data)) ?? []
    }

    func save(_ sensors: [RemoteSensor]) {
        guard let data = try? JSONEncoder().encode(sensors) else { return }
        defaults.set(data, forKey: key)
    }
}
