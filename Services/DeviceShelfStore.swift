import Foundation

/// Local, account-free storage for the device inventory, next to the scan
/// exports under Application Support.
final class DeviceShelfStore {
    private struct Payload: Codable {
        var version: Int
        var devices: [ShelfDevice]
    }

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("device-shelf.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var path: String { fileURL.path }

    func load() -> [ShelfDevice] {
        guard let data = try? Data(contentsOf: fileURL),
            let payload = try? decoder.decode(Payload.self, from: data)
        else { return [] }
        return payload.devices
    }

    func save(_ devices: [ShelfDevice]) {
        let payload = Payload(version: 1, devices: devices)
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
