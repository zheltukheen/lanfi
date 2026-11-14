import Foundation

/// DeviceShelf-style inventory: every device keeps its name, type, ports and
/// history across scans, whether or not it answered in the latest sweep.
enum DeviceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case router, computer, phone, tablet, tv, speaker, printer, camera, nas, console, iot, unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .router: return String(localized: "Router")
        case .computer: return String(localized: "Computer")
        case .phone: return String(localized: "Phone")
        case .tablet: return String(localized: "Tablet")
        case .tv: return String(localized: "TV / Media")
        case .speaker: return String(localized: "Speaker")
        case .printer: return String(localized: "Printer")
        case .camera: return String(localized: "Camera")
        case .nas: return String(localized: "NAS / Server")
        case .console: return String(localized: "Console")
        case .iot: return String(localized: "IoT")
        case .unknown: return String(localized: "Unknown")
        }
    }

    var icon: String {
        switch self {
        case .router: return "wifi.router"
        case .computer: return "desktopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .tv: return "tv"
        case .speaker: return "hifispeaker"
        case .printer: return "printer"
        case .camera: return "video"
        case .nas: return "externaldrive.connected.to.line.below"
        case .console: return "gamecontroller"
        case .iot: return "sensor"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}

struct DeviceShelfEvent: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case joined, returned, left, portsChanged
    }

    var id: UUID = UUID()
    var date: Date
    var kind: Kind
    var detail: String
}

/// A device as the inventory remembers it. `id` is the MAC when it is known,
/// so a DHCP address change does not create a second shelf entry.
struct ShelfDevice: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var mac: String?
    var ip: String
    var hostname: String?
    var vendor: String?
    /// What the device advertised about itself (mDNS/UPnP), kept across scans.
    var model: String?
    var manufacturer: String?
    var version: String?
    var role: String?
    var services: [String]?
    var category: DeviceCategory
    var openPorts: [UInt16]
    var firstSeen: Date
    var lastSeen: Date
    var isOnline: Bool
    var latencyMs: Double?
    var latencySamples: [Double]
    var isFavourite: Bool
    var alias: String?
    var notes: String?
    var scansSeen: Int
    var checks: Int
    var onlineChecks: Int
    var events: [DeviceShelfEvent]

    /// Asset-register fields. All optional so shelves written by older builds
    /// decode unchanged; the tag is backfilled on load.
    var assetTag: String? = nil
    var serialNumber: String? = nil
    var purchaseDate: Date? = nil
    var warrantyEnd: Date? = nil
    var location: String? = nil

    var warranty: DeviceWarranty { DeviceWarranty(end: warrantyEnd) }

    var displayName: String {
        if let alias, !alias.trimmingCharacters(in: .whitespaces).isEmpty { return alias }
        if let hostname, !hostname.isEmpty { return hostname }
        if let model, !model.isEmpty { return model }
        if let manufacturer, !manufacturer.isEmpty { return manufacturer }
        if let vendor, !vendor.isEmpty { return vendor }
        return String(localized: "Unknown device")
    }

    var makeLabel: String {
        manufacturer ?? vendor ?? "—"
    }

    var serviceLabels: [String] {
        services ?? []
    }

    var versionLabel: String {
        if let version, !version.isEmpty { return version }
        return "—"
    }

    /// Share of scans in which this device answered, 0…100.
    var availabilityPercent: Double? {
        guard checks > 0 else { return nil }
        return Double(onlineChecks) / Double(checks) * 100
    }

    var isNew: Bool { scansSeen <= 1 }

    var riskFindings: [DeviceRiskFinding] {
        DeviceRiskCatalog.findings(for: openPorts)
    }

    /// Low-severity noise (HTTP admin, UPnP, raw printing) is common on home
    /// routers and printers, so the Risks view only counts medium and above.
    var hasMeaningfulRisk: Bool {
        riskFindings.contains { $0.severity >= .medium }
    }
}
/// Where a device's warranty stands. Only one date is stored; the status is
/// derived so a shelf opened months later stays correct without edits.
enum DeviceWarranty: Equatable {
    case unknown
    case active(daysLeft: Int)
    case expiring(daysLeft: Int)
    case expired(daysAgo: Int)

    /// Warn this many days before the end date.
    static let warningWindow = 30

    init(end: Date?, now: Date = Date(), calendar: Calendar = .current) {
        guard let end else {
            self = .unknown
            return
        }
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)
            ).day ?? 0
        if days < 0 {
            self = .expired(daysAgo: -days)
        } else if days <= Self.warningWindow {
            self = .expiring(daysLeft: days)
        } else {
            self = .active(daysLeft: days)
        }
    }

    var isKnown: Bool { self != .unknown }

    var needsAttention: Bool {
        switch self {
        case .expiring, .expired: return true
        case .unknown, .active: return false
        }
    }

    var title: String {
        switch self {
        case .unknown: return String(localized: "No warranty date")
        case .active(let days):
            return String(format: String(localized: "%lld days left"), days)
        case .expiring(let days):
            return days == 0
                ? String(localized: "Ends today")
                : String(format: String(localized: "Ends in %lld days"), days)
        case .expired(let days):
            return String(format: String(localized: "Expired %lld days ago"), days)
        }
    }
}

/// Opaque identity for printed labels and `lanfi://device/...` links, so a
/// sticker on a box never carries the device's MAC address.
enum DeviceShelfAsset {
    static let tagPrefix = "LF-"

    static func newTag() -> String {
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).uppercased()
        return tagPrefix + hex
    }

    static func deepLink(for tag: String) -> String {
        "lanfi://device/" + tag
    }
}

// MARK: - Classification

enum DeviceClassifier {
    /// Best-effort type from the signals a LAN scan already has: the gateway
    /// flag, mDNS host names, the OUI vendor and the ports that answered.
    static func category(
        vendor: String?, hostname: String?, ports: [UInt16], isGateway: Bool,
        model: String? = nil, role: String? = nil
    ) -> DeviceCategory {
        if isGateway { return .router }
        let portSet = Set(ports)
        let name =
            "\((hostname ?? "").lowercased()) \((vendor ?? "").lowercased()) "
            + "\((model ?? "").lowercased()) \((role ?? "").lowercased())"

        if !portSet.isDisjoint(with: [9100, 631, 515]) { return .printer }
        if !portSet.isDisjoint(with: [554, 8554, 1935, 8000]) { return .camera }
        if !portSet.isDisjoint(with: [2049, 548, 139]) { return .nas }
        if portSet.contains(445) && portSet.contains(22) { return .nas }
        if portSet.contains(3389) { return .computer }
        if name.contains("printer") || name.contains("epson") || name.contains("brother")
            || name.contains("canon") || name.contains("hp")
        {
            return .printer
        }
        if name.contains("ipad") || name.contains("tablet") || name.contains("galaxy tab") {
            return .tablet
        }
        if name.contains("iphone") || name.contains("pixel") || name.contains("galaxy s")
            || name.contains("android") || portSet.contains(62078)
        {
            return .phone
        }
        if name.contains("appletv") || name.contains("apple tv") || name.contains("roku")
            || name.contains("chromecast") || name.contains("firetv") || name.contains("tv")
            || !portSet.isDisjoint(with: [8009, 8008, 9080, 49152])
        {
            return .tv
        }
        if name.contains("homepod") || name.contains("sonos") || name.contains("speaker")
            || portSet.contains(1400)
        {
            return .speaker
        }
        if name.contains("playstation") || name.contains("xbox") || name.contains("nintendo") {
            return .console
        }
        if name.contains("renderer") || name.contains("media server") || name.contains("mediaserver") {
            return .tv
        }
        if name.contains("macbook") || name.contains("imac") || name.contains("mac mini")
            || name.contains("desktop") || name.contains("laptop") || name.contains("windows")
            || !portSet.isDisjoint(with: [22, 88, 5900])
        {
            return .computer
        }
        if !portSet.isDisjoint(with: [1883, 8883, 5683, 6668, 9999]) { return .iot }
        if let vendor, !vendor.isEmpty, !portSet.isEmpty { return .computer }
        return .unknown
    }
}

// MARK: - Security findings

struct DeviceRiskFinding: Identifiable, Equatable, Sendable {
    enum Severity: Int, Codable, Comparable, Sendable {
        case info = 0, low = 1, medium = 2, high = 3

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .info: return String(localized: "Info")
            case .low: return String(localized: "Low")
            case .medium: return String(localized: "Medium")
            case .high: return String(localized: "High")
            }
        }
    }

    var port: UInt16
    var title: String
    var severity: Severity
    var advice: String

    var id: String { "\(port)-\(title)" }
}

enum DeviceRiskCatalog {
    private static let entries: [(port: UInt16, title: String, severity: DeviceRiskFinding.Severity, advice: String)] =
        [
            (
                23, String(localized: "Telnet is open"), .high,
                String(localized: "Disable Telnet and use SSH: credentials cross the LAN in clear text.")
            ),
            (
                21, String(localized: "FTP is open"), .high,
                String(localized: "Prefer SFTP/FTPS; anonymous FTP exposes files to the whole network.")
            ),
            (
                5900, String(localized: "VNC is open"), .high,
                String(localized: "Screen sharing on the LAN; set a strong password or a tunnel.")
            ),
            (
                27017, String(localized: "MongoDB is open"), .high,
                String(localized: "A database without auth is a common ransomware entry point.")
            ),
            (
                2375, String(localized: "Docker API without TLS"), .high,
                String(localized: "Anyone on the LAN can start containers on this host.")
            ),
            (
                445, String(localized: "SMB file sharing"), .medium,
                String(localized: "Keep it inside trusted networks and patch SMB regularly.")
            ),
            (
                139, String(localized: "NetBIOS is open"), .medium,
                String(localized: "Legacy sharing; disable it if the device does not need it.")
            ),
            (
                3389, String(localized: "Remote Desktop is open"), .medium,
                String(localized: "Restrict RDP to a VPN and enable account lockout.")
            ),
            (
                554, String(localized: "RTSP camera stream"), .medium,
                String(localized: "Camera streams often have default credentials. Change them.")
            ),
            (
                1883, String(localized: "MQTT without TLS"), .medium,
                String(localized: "Smart-home traffic in clear text; use 8883 with TLS.")
            ),
            (
                9200, String(localized: "Elasticsearch is open"), .medium,
                String(localized: "Search APIs are unauthenticated by default.")
            ),
            (
                80, String(localized: "Web admin over HTTP"), .low,
                String(localized: "Prefer HTTPS and change factory admin passwords.")
            ),
            (
                8080, String(localized: "Web admin over HTTP"), .low,
                String(localized: "Prefer HTTPS and change factory admin passwords.")
            ),
            (
                1900, String(localized: "UPnP / SSDP"), .low,
                String(localized: "UPnP can open router ports without asking; disable it if unused.")
            ),
            (
                9100, String(localized: "Raw printing"), .low,
                String(localized: "JetDirect printing accepts jobs from any LAN host.")
            ),
        ]

    static func findings(for ports: [UInt16]) -> [DeviceRiskFinding] {
        let open = Set(ports)
        return
            entries
            .filter { open.contains($0.port) }
            .map {
                DeviceRiskFinding(port: $0.port, title: $0.title, severity: $0.severity, advice: $0.advice)
            }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return lhs.port < rhs.port
            }
    }

    /// 100 for a quiet device, decreasing with the worst findings.
    static func score(for findings: [DeviceRiskFinding]) -> Int {
        let penalty = findings.reduce(0) { total, finding in
            switch finding.severity {
            case .high: return total + 35
            case .medium: return total + 15
            case .low: return total + 5
            case .info: return total
            }
        }
        return max(0, 100 - penalty)
    }
}

// MARK: - Merge

/// Folds one LAN scan into the stored inventory, keeping first/last seen,
/// latency samples, availability and a short event history per device.
enum DeviceShelfMerger {
    static let eventLimit = 40
    static let sampleLimit = 60

    static func deviceID(mac: String?, ip: String) -> String {
        if let mac, !mac.isEmpty { return mac.uppercased() }
        return "ip:\(ip)"
    }

    static func merge(_ stored: [ShelfDevice], scan: LANScanResult, now: Date = Date())
        -> [ShelfDevice]
    {
        // An empty sweep usually means Local Network access was denied or the
        // interface was down, not that every device left at once. Keeping the
        // shelf unchanged avoids a whole inventory flapping offline.
        guard !scan.devices.isEmpty || stored.isEmpty else { return stored }

        var remaining: [String: ShelfDevice] = [:]
        for device in stored where remaining[device.id] == nil {
            remaining[device.id] = device
        }

        var merged: [ShelfDevice] = []
        for lan in scan.devices {
            let id = deviceID(mac: lan.mac, ip: lan.ip)
            // Without Local Network permission an ICMP fallback sweep can list
            // bare addresses. Those are not identity, so they must not turn
            // into shelf entries; a known device still gets refreshed.
            let hasIdentity =
                lan.mac != nil || lan.hostname != nil || lan.vendor != nil
                || lan.model != nil || lan.manufacturer != nil || !lan.services.isEmpty
                || !lan.openPorts.isEmpty || lan.isGateway
            if remaining[id] == nil && !hasIdentity { continue }
            var record =
                remaining.removeValue(forKey: id)
                ?? ShelfDevice(
                    id: id,
                    mac: lan.mac,
                    ip: lan.ip,
                    hostname: lan.hostname,
                    vendor: lan.vendor,
                    model: lan.model,
                    manufacturer: lan.manufacturer,
                    version: lan.version,
                    role: lan.deviceType,
                    services: lan.services,
                    category: DeviceClassifier.category(
                        vendor: lan.vendor, hostname: lan.hostname, ports: lan.openPorts,
                        isGateway: lan.isGateway, model: lan.model, role: lan.deviceType),
                    openPorts: lan.openPorts.sorted(),
                    firstSeen: now,
                    lastSeen: now,
                    isOnline: true,
                    latencyMs: lan.latencyMilliseconds,
                    latencySamples: [],
                    isFavourite: false,
                    alias: nil,
                    notes: nil,
                    scansSeen: 0,
                    checks: 0,
                    onlineChecks: 0,
                    events: [],
                    assetTag: DeviceShelfAsset.newTag()
                )

            // Shelves written before the asset register existed get a tag on
            // their next merge, so printed labels never go stale.
            if record.assetTag == nil { record.assetTag = DeviceShelfAsset.newTag() }
            let isFirstScan = record.checks == 0
            if isFirstScan {
                record.events.append(
                    DeviceShelfEvent(
                        date: now, kind: .joined, detail: String(format: String(localized: "Joined %@"), scan.subnet)))
            } else if !record.isOnline {
                record.events.append(
                    DeviceShelfEvent(date: now, kind: .returned, detail: String(localized: "Back online")))
            }

            if !isFirstScan {
                let previous = Set(record.openPorts)
                let current = Set(lan.openPorts)
                if previous != current {
                    var parts: [String] = []
                    let opened = current.subtracting(previous).sorted()
                    let closed = previous.subtracting(current).sorted()
                    if !opened.isEmpty {
                        parts.append(
                            String(
                                format: String(localized: "opened %@"),
                                opened.map(String.init).joined(separator: ", ")))
                    }
                    if !closed.isEmpty {
                        parts.append(
                            String(
                                format: String(localized: "closed %@"),
                                closed.map(String.init).joined(separator: ", ")))
                    }
                    record.events.append(
                        DeviceShelfEvent(
                            date: now, kind: .portsChanged, detail: parts.joined(separator: " · ")))
                }
            }

            record.ip = lan.ip
            record.mac = lan.mac ?? record.mac
            if record.hostname == nil || record.hostname?.isEmpty == true {
                record.hostname = lan.hostname
            }
            if record.vendor == nil || record.vendor?.isEmpty == true {
                record.vendor = lan.vendor
            }
            if record.model == nil || record.model?.isEmpty == true {
                record.model = lan.model
            }
            if record.manufacturer == nil || record.manufacturer?.isEmpty == true {
                record.manufacturer = lan.manufacturer
            }
            if record.version == nil || record.version?.isEmpty == true {
                record.version = lan.version
            }
            if record.role == nil || record.role?.isEmpty == true {
                record.role = lan.deviceType
            }
            if (record.services ?? []).isEmpty, !lan.services.isEmpty {
                record.services = lan.services
            }
            let guessed = DeviceClassifier.category(
                vendor: record.vendor, hostname: record.hostname, ports: lan.openPorts,
                isGateway: lan.isGateway, model: record.model, role: record.role)
            if record.category == .unknown || (record.alias == nil && record.category != guessed) {
                if record.alias == nil { record.category = guessed }
            }
            record.openPorts = lan.openPorts.sorted()
            record.lastSeen = now
            record.isOnline = true
            record.scansSeen += 1
            record.checks += 1
            record.onlineChecks += 1
            if let latency = lan.latencyMilliseconds {
                record.latencyMs = latency
                record.latencySamples.append(latency)
                if record.latencySamples.count > sampleLimit {
                    record.latencySamples.removeFirst(record.latencySamples.count - sampleLimit)
                }
            }
            record.events = Array(record.events.suffix(eventLimit))
            merged.append(record)
        }

        for var record in remaining.values {
            record.checks += 1
            if record.isOnline {
                record.isOnline = false
                record.events.append(
                    DeviceShelfEvent(date: now, kind: .left, detail: String(localized: "Not seen in scan")))
                record.events = Array(record.events.suffix(eventLimit))
            }
            merged.append(record)
        }

        return merged.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            let left = IPv4Address(lhs.ip)?.value ?? UInt32.max
            let right = IPv4Address(rhs.ip)?.value ?? UInt32.max
            if left != right { return left < right }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
