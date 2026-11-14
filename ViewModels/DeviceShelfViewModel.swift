import Foundation

/// Owns the persistent device inventory: merges scans, filters the shelf,
/// keeps the user's names/favourites and produces exports.
final class DeviceShelfViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all, online, favourites, risky, warranty

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .online: return String(localized: "Online")
            case .favourites: return String(localized: "Favourites")
            case .risky: return String(localized: "Risks")
            case .warranty: return String(localized: "Warranty")
            }
        }

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .online: return "bolt.horizontal.circle"
            case .favourites: return "star"
            case .risky: return "exclamationmark.shield"
            case .warranty: return "calendar.badge.exclamationmark"
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
        backfillAssetTags()
        selectedID = devices.first?.id
    }

    var filteredDevices: [ShelfDevice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return devices.filter { device in
            switch filter {
            case .all: break
            case .online: if !device.isOnline { return false }
            case .favourites: if !device.isFavourite { return false }
            case .risky: if !device.hasMeaningfulRisk { return false }
            case .warranty: if !device.warranty.needsAttention { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack = [
                device.displayName, device.hostname ?? "", device.ip, device.mac ?? "",
                device.vendor ?? "", device.manufacturer ?? "", device.model ?? "",
                device.role ?? "", device.category.title, device.serviceLabels.joined(separator: " "),
                device.assetTag ?? "", device.serialNumber ?? "", device.location ?? "",
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
        devices.filter(\.hasMeaningfulRisk).count
    }
    /// Warranties that expire soon or already have.
    var warrantyAttentionCount: Int {
        devices.filter { $0.warranty.needsAttention }.count
    }

    func device(id: String) -> ShelfDevice? { devices.first { $0.id == id } }

    func device(assetTag: String) -> ShelfDevice? {
        let tag = assetTag.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return devices.first { $0.assetTag?.uppercased() == tag }
    }

    /// Shelves written before the asset register existed need a stable tag so a
    /// printed label keeps resolving to the same device.
    private func backfillAssetTags() {
        var changed = false
        for index in devices.indices where devices[index].assetTag == nil {
            devices[index].assetTag = DeviceShelfAsset.newTag()
            changed = true
        }
        if changed { store.save(devices) }
    }

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
        backfillAssetTags()
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

    func setSerial(_ serial: String, for id: String) {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.serialNumber = trimmed.isEmpty ? nil : trimmed }
    }

    func setLocation(_ location: String, for id: String) {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.location = trimmed.isEmpty ? nil : trimmed }
    }

    func setPurchaseDate(_ date: Date?, for id: String) {
        update(id) { $0.purchaseDate = date }
    }

    func setWarrantyEnd(_ date: Date?, for id: String) {
        update(id) { $0.warrantyEnd = date }
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
            "name,ip,mac,vendor,manufacturer,model,version,role,services,category,online,open_ports,availability_percent,first_seen,last_seen,favourite,notes,asset_tag,serial_number,location,purchase_date,warranty_end,warranty_status"
        ]
        let formatter = ISO8601DateFormatter()
        for device in devices {
            let fields = [
                device.displayName,
                device.ip,
                device.mac ?? "",
                device.vendor ?? "",
                device.manufacturer ?? "",
                device.model ?? "",
                device.version ?? "",
                device.role ?? "",
                device.serviceLabels.joined(separator: " "),
                device.category.title,
                device.isOnline ? "yes" : "no",
                device.openPorts.map(String.init).joined(separator: " "),
                device.availabilityPercent.map { String(format: "%.1f", $0) } ?? "",
                formatter.string(from: device.firstSeen),
                formatter.string(from: device.lastSeen),
                device.isFavourite ? "yes" : "no",
                device.notes ?? "",
                device.assetTag ?? "",
                device.serialNumber ?? "",
                device.location ?? "",
                device.purchaseDate.map { Self.day.string(from: $0) } ?? "",
                device.warrantyEnd.map { Self.day.string(from: $0) } ?? "",
                device.warranty.isKnown ? device.warranty.title : "",
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
            if let model = device.model { row["model"] = model }
            if let manufacturer = device.manufacturer { row["manufacturer"] = manufacturer }
            if let version = device.version { row["version"] = version }
            if let role = device.role { row["role"] = role }
            if let services = device.services, !services.isEmpty { row["services"] = services }
            if let availability = device.availabilityPercent {
                row["availabilityPercent"] = (availability * 10).rounded() / 10
            }
            if let notes = device.notes { row["notes"] = notes }
            if let assetTag = device.assetTag { row["assetTag"] = assetTag }
            if let serial = device.serialNumber { row["serialNumber"] = serial }
            if let location = device.location { row["location"] = location }
            if let purchase = device.purchaseDate {
                row["purchaseDate"] = Self.day.string(from: purchase)
            }
            if let end = device.warrantyEnd {
                row["warrantyEnd"] = Self.day.string(from: end)
                row["warrantyStatus"] = device.warranty.title
            }
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

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
