import Foundation

/// Owns the persistent device inventory: merges scans, filters the shelf,
/// keeps the user's names/favourites and produces exports.
final class DeviceShelfViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all, online, favourites, risky

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .online: return String(localized: "Online")
            case .favourites: return String(localized: "Favourites")
            case .risky: return String(localized: "Risks")
            }
        }

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .online: return "bolt.horizontal.circle"
            case .favourites: return "star"
            case .risky: return "exclamationmark.shield"
            }
        }
    }

    @Published private(set) var devices: [ShelfDevice] = []
    @Published var searchText = ""
    @Published var filter: Filter = .all
    @Published var selectedID: String?
    @Published private(set) var lastScanSubnet: String?
    @Published private(set) var lastMergedAt: Date?

    private let store: DeviceShelfStore

    init(store: DeviceShelfStore = DeviceShelfStore()) {
        self.store = store
        devices = store.load()
        selectedID = devices.first?.id
    }

    var filteredDevices: [ShelfDevice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return devices.filter { device in
            switch filter {
            case .all: break
            case .online: if !device.isOnline { return false }
            case .favourites: if !device.isFavourite { return false }
            case .risky:
                if DeviceRiskCatalog.findings(for: device.openPorts).isEmpty { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack = [
                device.displayName, device.hostname ?? "", device.ip, device.mac ?? "",
                device.vendor ?? "", device.category.title,
            ].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    var selectedDevice: ShelfDevice? {
        devices.first { $0.id == selectedID }
    }

    var onlineCount: Int { devices.filter(\.isOnline).count }
    var favouriteCount: Int { devices.filter(\.isFavourite).count }
    var riskyDeviceCount: Int {
        devices.filter { !DeviceRiskCatalog.findings(for: $0.openPorts).isEmpty }.count
    }

    func device(id: String) -> ShelfDevice? { devices.first { $0.id == id } }

    // MARK: - Scanning

    func merge(_ scan: LANScanResult) {
        devices = DeviceShelfMerger.merge(devices, scan: scan)
        lastScanSubnet = scan.subnet
        lastMergedAt = scan.scannedAt
        store.save(devices)
        if selectedID == nil || !devices.contains(where: { $0.id == selectedID }) {
            selectedID = filteredDevices.first?.id ?? devices.first?.id
        }
    }

    func reload() {
        devices = store.load()
        if selectedID == nil { selectedID = devices.first?.id }
    }

    // MARK: - Editing

    func toggleFavourite(_ id: String) {
        update(id) { $0.isFavourite.toggle() }
    }

    func setAlias(_ alias: String, for id: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.alias = trimmed.isEmpty ? nil : trimmed }
    }

    func setNotes(_ notes: String, for id: String) {
        update(id) { $0.notes = notes.isEmpty ? nil : notes }
    }

    func setCategory(_ category: DeviceCategory, for id: String) {
        update(id) { $0.category = category }
    }

    func forget(_ id: String) {
        devices.removeAll { $0.id == id }
        if selectedID == id { selectedID = filteredDevices.first?.id }
        store.save(devices)
    }

    func clearAll() {
        devices.removeAll()
        selectedID = nil
        lastScanSubnet = nil
        lastMergedAt = nil
        store.save(devices)
    }

    private func update(_ id: String, _ change: (inout ShelfDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[index])
        store.save(devices)
    }

    // MARK: - Export

    var csv: String {
        var rows = [
            "name,ip,mac,vendor,category,online,open_ports,availability_percent,first_seen,last_seen,favourite,notes"
        ]
        let formatter = ISO8601DateFormatter()
        for device in devices {
            let fields = [
                device.displayName,
                device.ip,
                device.mac ?? "",
                device.vendor ?? "",
                device.category.title,
                device.isOnline ? "yes" : "no",
                device.openPorts.map(String.init).joined(separator: " "),
                device.availabilityPercent.map { String(format: "%.1f", $0) } ?? "",
                formatter.string(from: device.firstSeen),
                formatter.string(from: device.lastSeen),
                device.isFavourite ? "yes" : "no",
                device.notes ?? "",
            ]
            rows.append(fields.map(Self.escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let rows: [[String: Any]] = devices.map { device in
            var row: [String: Any] = [
                "name": device.displayName,
                "ip": device.ip,
                "category": device.category.rawValue,
                "online": device.isOnline,
                "openPorts": device.openPorts.map(Int.init),
                "favourite": device.isFavourite,
                "riskScore": DeviceRiskCatalog.score(
                    for: DeviceRiskCatalog.findings(for: device.openPorts)),
            ]
            if let mac = device.mac { row["mac"] = mac }
            if let vendor = device.vendor { row["vendor"] = vendor }
            if let hostname = device.hostname { row["hostname"] = hostname }
            if let availability = device.availabilityPercent {
                row["availabilityPercent"] = (availability * 10).rounded() / 10
            }
            if let notes = device.notes { row["notes"] = notes }
            row["firstSeen"] = ISO8601DateFormatter().string(from: device.firstSeen)
            row["lastSeen"] = ISO8601DateFormatter().string(from: device.lastSeen)
            return row
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["devices": rows], options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{\"devices\":[]}" }
        return text
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
