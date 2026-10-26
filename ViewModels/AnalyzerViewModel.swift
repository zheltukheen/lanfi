//  AnalyzerViewModel.swift

import Foundation
import Combine
import CoreWLAN
import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

// MARK: - Enums & Settings

enum SignalDisplayMode: String, CaseIterable, Identifiable {
    case dbm = "dBm"
    case percent = "%"
    var id: String { rawValue }
}

enum NetworkRemovalInterval: TimeInterval, CaseIterable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: TimeInterval { rawValue }

    var title: String {
        switch self {
        case .oneMinute: return "1 min"
        case .twoMinutes: return "2 min"
        case .fiveMinutes: return "5 min"
        case .tenMinutes: return "10 min"
        }
    }
}

// MARK: - Column Definitions

enum ColumnId: String, CaseIterable, Codable {
    case apName
    case amendments
    case annotations
    case bssid
    case band
    case basicRates
    case beaconAirtime
    case beaconInterval
    case beaconMode
    case beaconRate
    case centerFrequency
    case channel
    case channelUtilization
    case channelWidth
    case clients
    case congestion
    case count
    case countryCode
    case fastTransition
    case firstSeen
    case generation
    case ieCount
    case ieTotalLength
    case lastSeen
    case maxBasicRate
    case maxRate
    case minBasicRate
    case minRate
    case mode
    case networkName
    case noise
    case protectionMode
    case quality
    case snr
    case security
    case seen
    case signal
    case stations
    case streams
    case type
    case uptime
    case vendor
    case wideChannel

    var defaultTitle: String {
        switch self {
        case .apName: return "AP Name"
        case .amendments: return "Amendments"
        case .annotations: return "Annotations"
        case .bssid: return "BSSID"
        case .band: return "Band"
        case .basicRates: return "Basic Rates"
        case .beaconAirtime: return "Beacon Airtime"
        case .beaconInterval: return "Beacon Interval"
        case .beaconMode: return "Beacon Mode"
        case .beaconRate: return "Beacon Rate"
        case .centerFrequency: return "Center Frequency"
        case .channel: return "Channel"
        case .channelUtilization: return "Channel Utilization"
        case .channelWidth: return "Width"
        case .clients: return "Clients"
        case .congestion: return "Congestion"
        case .count: return "Count"
        case .countryCode: return "Country Code"
        case .fastTransition: return "Fast Transition"
        case .firstSeen: return "First Seen"
        case .generation: return "Generation"
        case .ieCount: return "IE Count"
        case .ieTotalLength: return "IE Total Length"
        case .lastSeen: return "Last Seen"
        case .maxBasicRate: return "Max Basic Rate"
        case .maxRate: return "Max Rate"
        case .minBasicRate: return "Min Basic Rate"
        case .minRate: return "Min Rate"
        case .mode: return "Mode"
        case .networkName: return "Network Name"
        case .noise: return "Noise"
        case .protectionMode: return "Protection Mode"
        case .quality: return "Quality"
        case .snr: return "SNR"
        case .security: return "Security"
        case .seen: return "Seen"
        case .signal: return "Signal"
        case .stations: return "Stations"
        case .streams: return "Streams"
        case .type: return "Type"
        case .uptime: return "Uptime"
        case .vendor: return "Vendor"
        case .wideChannel: return "Wide Channel"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .signal, .quality:
            return 80
        case .channel, .congestion:
            return 70
        case .count, .seen, .clients, .stations, .streams, .noise, .snr, .wideChannel:
            return 70
        case .band:
            return 75
        case .generation, .mode:
            return 85
        case .type:
            return 90
        case .security:
            return 100
        case .channelWidth, .maxRate, .minRate, .maxBasicRate, .minBasicRate, .beaconInterval, .beaconRate:
            return 75
        case .centerFrequency, .countryCode, .fastTransition, .beaconMode, .beaconAirtime, .channelUtilization:
            return 110
        case .firstSeen, .lastSeen, .uptime:
            return 130
        case .networkName:
            return 150
        case .bssid:
            return 140
        case .vendor:
            return 130
        case .basicRates, .annotations, .apName:
            return 150
        case .amendments, .ieCount, .ieTotalLength:
            return 120
        case .protectionMode:
            return 160
        }
    }

    var defaultAlignment: ColumnAlignment {
        switch self {
        case .signal, .channel, .channelWidth, .count, .seen, .clients, .stations, .streams, .noise, .snr,
            .centerFrequency, .channelUtilization, .beaconInterval, .beaconRate, .beaconAirtime, .maxRate, .minRate,
            .maxBasicRate, .minBasicRate, .ieCount, .ieTotalLength, .uptime, .quality, .congestion:
            return .right
        case .wideChannel, .fastTransition:
            return .center
        default:
            return .left
        }
    }

    var defaultVisibility: Bool {
        switch self {
        case .networkName, .signal, .quality, .band, .channel, .channelWidth,
            .security, .vendor, .bssid, .maxRate, .mode:
            return true
        default:
            return false
        }
    }

    /// Sensible out-of-the-box column order: identity, signal, interpretation,
    /// radio details, then the long tail of 802.11 fields.
    static let displayOrder: [ColumnId] = [
        .networkName, .signal, .quality, .band, .channel, .channelWidth,
        .security, .vendor, .bssid, .generation, .maxRate, .mode, .snr, .noise,
        .seen, .lastSeen, .firstSeen, .uptime, .congestion, .channelUtilization,
        .clients, .stations, .streams, .countryCode, .fastTransition,
        .protectionMode, .beaconInterval, .beaconRate, .beaconAirtime, .wideChannel,
        .centerFrequency, .basicRates, .minRate, .minBasicRate,
        .maxBasicRate, .amendments, .annotations, .apName, .count, .ieCount,
        .ieTotalLength, .type, .beaconMode,
    ]
}

enum ColumnAlignment: Int, Codable {
    case left = 0
    case center = 1
    case right = 2

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

// MARK: - Models

struct ColumnDefinition: Identifiable, Codable {
    var id: String
    var title: String
    var width: CGFloat
    var isVisible: Bool
    var order: Int
    var alignment: ColumnAlignment = .left
    var isPinned: Bool = false
    var customTitle: String? = nil

    var displayTitle: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        return title
    }

    static let defaults: [ColumnDefinition] = {
        ColumnId.displayOrder.enumerated().map { index, column in
            ColumnDefinition(
                id: column.rawValue,
                title: column.defaultTitle,
                width: column.defaultWidth,
                isVisible: column.defaultVisibility,
                order: index,
                alignment: column.defaultAlignment
            )
        }
    }()
}

enum SidebarCategory: CaseIterable {
    case networkName
    case mode
    case channel
    case channelWidth
    case security
    case accessPoint
    case vendor

    var title: String {
        switch self {
        case .networkName: return "Network Name"
        case .mode: return "Mode"
        case .channel: return "Channel"
        case .channelWidth: return "Width"
        case .security: return "Security"
        case .accessPoint: return "Access Point"
        case .vendor: return "Vendor"
        }
    }
}

// MARK: - ViewModel

// @MainActor гарантирует, что все обновления @Published идут в UI-потоке.
// Это решает проблему "Publishing changes from within view updates".
@MainActor
class AnalyzerViewModel: ObservableObject {

    // MARK: - Dependencies
    private let scanner = WiFiScanner()  // Actor
    private let locationManager = LocationManager()
    private let refreshIntervalKey = "RefreshIntervalSeconds"
    private let historyWindowSeconds: TimeInterval = 180

    // MARK: - Internal State
    private var persistentNetworks: [String: NetworkModel] = [:]
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isScanning = false

    // MARK: - Color Logic

    /// Глобальный генератор цвета для сети, чтобы во всех графах он был одинаковым
    func colorFor(networkId: String) -> Color {
        let hash = stableHash(networkId)
        // hue: 0.0 ... 1.0
        let hue = Double(hash % 1000) / 1000.0
        // Высокая яркость и насыщенность для темного фона
        return Color(hue: hue, saturation: 0.85, brightness: 1.0)
    }

    private func stableHash(_ input: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    // MARK: - Helpers

    /// Конвертация dBm в проценты (0% = -100dBm, 100% = -50dBm)
    func convertToPercent(_ dbm: Int) -> Double {
        let val = Double(dbm)
        if val <= -100 { return 0 }
        if val >= -50 { return 100 }
        return (val + 100) * 2
    }

    // MARK: - Published Properties (UI Binding)
    @Published var networks: [NetworkModel] = []
    @Published var baseFilteredNetworks: [NetworkModel] = []
    @Published var currentConnectedBSSID: String? = nil
    @Published var signalHistory: [String: [Int]] = [:]
    @Published private(set) var analysis: AnalysisReport = .empty
    @Published var selectedNetworkId: String? = nil
    @Published var highlightConnectedNetworks: Bool = true { didSet { savePreferences() } }

    // Settings & Filters
    @Published var filterBand24 = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var filterBand5 = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var filterBand6 = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var minSignalThreshold: Double = -100 { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var searchText: String = ""  // Обрабатывается через debounce в init

    @Published var removeAfterInterval: NetworkRemovalInterval = .twoMinutes {
        didSet { requestFilterUpdate(); savePreferences() }
    }
    @Published var signalDisplayMode: SignalDisplayMode = .dbm { didSet { savePreferences() } }

    @Published var refreshInterval: Double = 3.0
    @Published var isSortAscending: Bool = false { didSet { applyFilters(); savePreferences() } }
    @Published var currentSortKey: String? = ColumnId.signal.rawValue { didSet { applyFilters(); savePreferences() } }
    @Published var columnDefinitions: [ColumnDefinition] = ColumnDefinition.defaults

    // Quick filters (sidebar)
    @Published var quickFilterNetworkName: String? { didSet { requestFilterUpdate() } }
    @Published var quickFilterMode: String? { didSet { requestFilterUpdate() } }
    @Published var quickFilterChannel: String? { didSet { requestFilterUpdate() } }
    @Published var quickFilterChannelWidth: String? { didSet { requestFilterUpdate() } }
    @Published var quickFilterSecurity: String? { didSet { requestFilterUpdate() } }
    @Published var quickFilterAccessPoint: String? { didSet { requestFilterUpdate() } }
    @Published var quickFilterVendor: String? { didSet { requestFilterUpdate() } }

    @Published var isLocationAuthorized = false
    @Published var errorMessage: String?
    @Published private(set) var lastScanDate: Date?

    // MARK: - Initialization
    init() {
        setupBindings()
        loadPreferences()
        loadColumnSettings()
        // Стартуем сканирование сразу, но реальные данные пойдут только после разрешения Location
        startScanningLoop()
    }

    private func setupBindings() {
        // Location Status Binding
        locationManager.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                let authorized = (status == .authorizedAlways || status == .authorized)
                self.isLocationAuthorized = authorized
                if authorized {
                    self.refresh()
                }
            }
            .store(in: &cancellables)

        // Search Debounce (Optimization)
        // Чтобы не пересчитывать список на каждую букву при быстром вводе
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyFilters() }
            .store(in: &cancellables)
    }

    // MARK: - Scanning Loop

    func startScanningLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer?.tolerance = max(0.2, refreshInterval * 0.1)
    }

    func updateRefreshInterval(to newValue: Double) {
        refreshInterval = newValue
        UserDefaults.standard.set(newValue, forKey: refreshIntervalKey)
        startScanningLoop()
    }

    // MARK: - Refresh Logic (Async/Await)

    func refresh() {
        guard !isScanning else { return }
        isScanning = true

        let currentBSSID = CWWiFiClient.shared().interface()?.bssid()?.uppercased()

        // Используем Task для вызова метода Actor-а
        Task {
            defer { isScanning = false }

            do {
                // Асинхронный вызов к WiFiScanner (не блокирует Main Thread)
                let scannedList = try await scanner.scan()

                // Следующий код выполняется автоматически на MainActor, т.к. класс помечен им
                self.errorMessage = nil
                self.currentConnectedBSSID = currentBSSID
                self.lastScanDate = Date()
                self.mergeNetworks(scannedList)

            } catch let error as WiFiError {
                // Обработка типизированных ошибок
                if case .interfaceNotFound = error {
                    self.errorMessage = "Wi-Fi is off"
                } else if case .wifiPoweredOff = error {
                    self.errorMessage = "Wi-Fi is off"
                } else {
                    self.errorMessage = error.localizedDescription
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Data Processing

    private func mergeNetworks(_ newScan: [NetworkModel]) {
        let now = Date()

        // 1. Update Existing
        for net in newScan {
            let existing = persistentNetworks[net.id]
            let updated = observing(net: net, existing: existing, now: now)
            persistentNetworks[net.id] = updated
            updateSignalHistory(for: updated)
        }

        // 2. Cleanup Old
        let threshold = now.addingTimeInterval(-removeAfterInterval.rawValue)
        let keysToRemove = persistentNetworks.filter { $0.value.lastSeen ?? Date.distantPast < threshold }.map {
            $0.key
        }

        for key in keysToRemove {
            persistentNetworks.removeValue(forKey: key)
            signalHistory.removeValue(forKey: key)
        }

        analysis = NetworkAnalyzer.analyze(networks: Array(persistentNetworks.values))
        applyFilters()
    }

    private func observing(net: NetworkModel, existing: NetworkModel?, now: Date) -> NetworkModel {
        let firstSeen = existing?.firstSeen ?? now
        let count = (existing?.count ?? 0) + 1

        return NetworkModel(
            id: net.id,
            bssid: net.bssid,
            ssid: net.ssid,
            band: net.band,
            channel: net.channel,
            channelWidthMHz: net.channelWidthMHz,
            generation: net.generation,
            security: net.security,
            vendor: net.vendor,
            mode: net.mode,
            signal: net.signal,
            noise: net.noise,
            snr: net.snr,
            basicRates: net.basicRates,
            minBasicRate: net.minBasicRate,
            maxBasicRate: net.maxBasicRate,
            minRate: net.minRate,
            maxRate: net.maxRate,
            centerFrequency: net.centerFrequency,
            channelUtilization: net.channelUtilization,
            beaconInterval: net.beaconInterval,
            beaconRate: net.beaconRate,
            beaconAirtime: net.beaconAirtime,
            beaconMode: net.beaconMode,
            countryCode: net.countryCode,
            fastTransition: net.fastTransition,
            protectionMode: net.protectionMode,
            stations: net.stations,
            clients: net.clients,
            streams: net.streams,
            type: net.type,
            wps: net.wps,
            wpsEnabled: net.wpsEnabled,
            pmfRequired: net.pmfRequired,
            ieCount: net.ieCount,
            ieTotalLength: net.ieTotalLength,
            ratesEstimated: net.ratesEstimated,
            informationElements: net.informationElements,
            count: count,
            firstSeen: firstSeen,
            lastSeen: now
        )
    }

    private func updateSignalHistory(for net: NetworkModel) {
        let maxPoints = maxHistoryPoints()
        var history = signalHistory[net.id] ?? []
        history.append(net.signal)
        if history.count > maxPoints {
            history.removeFirst(history.count - maxPoints)
        }
        signalHistory[net.id] = history
    }

    // MARK: - Filtering & Sorting

    private func requestFilterUpdate() {
        // Простой debounce не нужен здесь, так как toggles нажимаются редко.
        // Выполняем сразу.
        applyFilters()
    }

    private func applyFilters() {
        let allItems = Array(persistentNetworks.values)
        let query = searchText.lowercased()

        // 1. Filter
        var baseFiltered = allItems.filter { net in
            if !filterBand24 && net.band == .band24 { return false }
            if !filterBand5 && net.band == .band5 { return false }
            if !filterBand6 && net.band == .band6 { return false }
            if Double(net.signal) < minSignalThreshold { return false }

            if !query.isEmpty {
                let matches =
                    net.ssid.lowercased().contains(query) || net.bssid.lowercased().contains(query)
                    || net.vendor.lowercased().contains(query)
                if !matches { return false }
            }
            return true
        }

        baseFilteredNetworks = baseFiltered

        // 2. Quick Filters (Sidebar)
        if let value = quickFilterNetworkName {
            baseFiltered = baseFiltered.filter { $0.displaySSID == value }
        }
        if let value = quickFilterMode {
            baseFiltered = baseFiltered.filter { $0.mode == value }
        }
        if let value = quickFilterChannel {
            baseFiltered = baseFiltered.filter { String($0.channel) == value }
        }
        if let value = quickFilterChannelWidth {
            baseFiltered = baseFiltered.filter { $0.channelWidthLabel == value }
        }
        if let value = quickFilterSecurity {
            baseFiltered = baseFiltered.filter { $0.security == value }
        }
        if let value = quickFilterAccessPoint {
            let target = value == "<Hidden>" ? "" : value
            baseFiltered = baseFiltered.filter { $0.bssid == target }
        }
        if let value = quickFilterVendor {
            baseFiltered = baseFiltered.filter { $0.vendor == value }
        }

        var filtered = baseFiltered

        // 3. Sort
        if let keyString = currentSortKey, let key = ColumnId(rawValue: keyString) {
            filtered.sort { p1, p2 in
                let forward = compare(p1, p2, by: key)
                let backward = compare(p2, p1, by: key)
                if !forward && !backward { return p1.id < p2.id }
                return isSortAscending ? forward : backward
            }
        }

        self.networks = filtered
        if let selectedId = selectedNetworkId, !filtered.contains(where: { $0.id == selectedId }) {
            selectedNetworkId = nil
        }
    }

    // MARK: - Public Methods

    func sort(by key: String, ascending: Bool) {
        currentSortKey = key
        isSortAscending = ascending
        // applyFilters вызовется автоматически через didSet
    }

    func formatSignal(_ dbm: Int) -> String {
        switch signalDisplayMode {
        case .dbm: return "\(dbm)"
        case .percent:
            // Аппроксимация: -100dBm = 0%, -50dBm = 100%
            let quality = max(0, min(100, (dbm + 100) * 2))
            return "\(quality)%"
        }
    }

    func textForColumn(id: String, net: NetworkModel) -> String {
        guard let column = ColumnId(rawValue: id) else { return "-" }
        switch column {
        case .apName: return apName(for: net)
        case .amendments: return net.generationLabel
        case .annotations: return annotations(for: net)
        case .bssid: return net.bssid.isEmpty ? "-" : net.bssid
        case .band: return net.bandLabel
        case .basicRates: return net.basicRatesLabel
        case .beaconAirtime: return formatOptionalDouble(net.beaconAirtime)
        case .beaconInterval: return formatOptionalInt(net.beaconInterval)
        case .beaconMode: return net.beaconMode ?? net.mode
        case .beaconRate: return formatOptionalDouble(net.beaconRate)
        case .centerFrequency: return net.centerFrequencyLabel
        case .channel: return "\(net.channel)"
        case .channelUtilization: return formatOptionalInt(net.channelUtilization)
        case .channelWidth: return net.channelWidthLabel
        case .clients: return formatOptionalInt(net.clients)
        case .congestion: return metrics(for: net)?.congestionScore.description ?? "-"
        case .count: return "\(net.count)"
        case .countryCode: return net.countryCode ?? "-"
        case .fastTransition: return formatOptionalBool(net.fastTransition)
        case .firstSeen: return formatDate(net.firstSeen)
        case .generation: return net.generationLabel
        case .ieCount: return formatOptionalInt(net.ieCount)
        case .ieTotalLength: return formatOptionalInt(net.ieTotalLength)
        case .lastSeen: return formatDate(net.lastSeen)
        case .maxBasicRate: return net.maxBasicRateLabel
        case .maxRate: return net.maxRateLabel
        case .minBasicRate: return net.minBasicRateLabel
        case .minRate: return net.minRateLabel
        case .mode: return net.mode
        case .networkName: return net.displaySSID
        case .noise: return net.noiseLabel
        case .protectionMode: return net.protectionMode ?? "-"
        case .quality: return metrics(for: net)?.qualityScore.description ?? "-"
        case .snr: return net.snrLabel
        case .security: return net.security
        case .seen: return "\(net.seen)"
        case .signal: return formatSignal(net.signal)
        case .stations: return formatOptionalInt(net.stations)
        case .streams: return formatOptionalInt(net.streams)
        case .type: return net.type ?? "-"
        case .uptime:
            if let uptime = net.uptimeSeconds { return formatDuration(seconds: uptime) }
            return "-"
        case .vendor: return net.vendor
        case .wideChannel: return net.wideChannelLabel
        }
    }

    private func apName(for net: NetworkModel) -> String {
        if net.vendor != "-" { return net.vendor }
        return net.displaySSID
    }

    private func annotations(for net: NetworkModel) -> String {
        var parts: [String] = []
        if net.ssid.isEmpty { parts.append("Hidden SSID") }
        if net.ratesEstimated { parts.append("Est. rates") }
        if let current = currentConnectedBSSID, !current.isEmpty, net.bssid == current {
            parts.append("Connected")
        }
        if let metric = metrics(for: net) {
            if metric.grade == .poor { parts.append("Poor quality") }
            if metric.interferenceLoad >= 0.5 { parts.append("Congested") }
        }
        if net.security.lowercased().contains("open") { parts.append("Open") }
        return parts.isEmpty ? "-" : parts.joined(separator: ", ")
    }

    private func compare(_ a: NetworkModel, _ b: NetworkModel, by key: ColumnId) -> Bool {
        switch key {
        case .apName: return compareText(apName(for: a), apName(for: b))
        case .amendments: return a.generation.sortOrder < b.generation.sortOrder
        case .annotations: return compareText(annotations(for: a), annotations(for: b))
        case .bssid: return compareText(a.bssid, b.bssid)
        case .band: return a.band.sortOrder < b.band.sortOrder
        case .basicRates: return (a.maxBasicRate ?? 0) < (b.maxBasicRate ?? 0)
        case .beaconAirtime: return (a.beaconAirtime ?? 0) < (b.beaconAirtime ?? 0)
        case .beaconInterval: return (a.beaconInterval ?? 0) < (b.beaconInterval ?? 0)
        case .beaconMode: return compareText(a.beaconMode ?? a.mode, b.beaconMode ?? b.mode)
        case .beaconRate: return (a.beaconRate ?? 0) < (b.beaconRate ?? 0)
        case .centerFrequency: return (a.centerFrequency ?? 0) < (b.centerFrequency ?? 0)
        case .channel: return a.channel < b.channel
        case .channelUtilization: return (a.channelUtilization ?? 0) < (b.channelUtilization ?? 0)
        case .channelWidth: return a.channelWidthMHz < b.channelWidthMHz
        case .clients: return (a.clients ?? 0) < (b.clients ?? 0)
        case .congestion: return (metrics(for: a)?.congestionScore ?? 0) < (metrics(for: b)?.congestionScore ?? 0)
        case .count: return a.count < b.count
        case .countryCode: return compareText(a.countryCode ?? "", b.countryCode ?? "")
        case .fastTransition: return boolToInt(a.fastTransition) < boolToInt(b.fastTransition)
        case .firstSeen: return (a.firstSeen ?? Date.distantPast) < (b.firstSeen ?? Date.distantPast)
        case .generation: return a.generation.sortOrder < b.generation.sortOrder
        case .ieCount: return (a.ieCount ?? 0) < (b.ieCount ?? 0)
        case .ieTotalLength: return (a.ieTotalLength ?? 0) < (b.ieTotalLength ?? 0)
        case .lastSeen: return (a.lastSeen ?? Date.distantPast) < (b.lastSeen ?? Date.distantPast)
        case .maxBasicRate: return (a.maxBasicRate ?? 0) < (b.maxBasicRate ?? 0)
        case .maxRate: return (a.maxRate ?? 0) < (b.maxRate ?? 0)
        case .minBasicRate: return (a.minBasicRate ?? 0) < (b.minBasicRate ?? 0)
        case .minRate: return (a.minRate ?? 0) < (b.minRate ?? 0)
        case .mode: return compareText(a.mode, b.mode)
        case .networkName: return compareText(a.displaySSID, b.displaySSID)
        case .noise: return (a.noise ?? 0) < (b.noise ?? 0)
        case .protectionMode: return compareText(a.protectionMode ?? "", b.protectionMode ?? "")
        case .quality: return (metrics(for: a)?.qualityScore ?? 0) < (metrics(for: b)?.qualityScore ?? 0)
        case .snr: return (a.snr ?? 0) < (b.snr ?? 0)
        case .security: return compareText(a.security, b.security)
        case .seen: return a.seen < b.seen
        case .signal: return a.signal < b.signal
        case .stations: return (a.stations ?? 0) < (b.stations ?? 0)
        case .streams: return (a.streams ?? 0) < (b.streams ?? 0)
        case .type: return compareText(a.type ?? "", b.type ?? "")
        case .uptime: return (a.uptimeSeconds ?? 0) < (b.uptimeSeconds ?? 0)
        case .vendor: return compareText(a.vendor, b.vendor)
        case .wideChannel: return (a.channelWidthMHz >= 80 ? 1 : 0) < (b.channelWidthMHz >= 80 ? 1 : 0)
        }
    }

    private func compareText(_ a: String, _ b: String) -> Bool {
        a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    private func boolToInt(_ value: Bool?) -> Int {
        value == true ? 1 : 0
    }

    private func formatOptionalInt(_ value: Int?) -> String {
        guard let value else { return "-" }
        return "\(value)"
    }

    private func formatOptionalDouble(_ value: Double?) -> String {
        guard let value, value > 0 else { return "-" }
        return String(format: "%.0f", value)
    }

    private func formatOptionalBool(_ value: Bool?) -> String {
        guard let value else { return "-" }
        return value ? "Yes" : "No"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%02dh %02dm %02ds", hours, minutes, secs)
        }
        if minutes > 0 {
            return String(format: "%02dm %02ds", minutes, secs)
        }
        return "\(secs)s"
    }

    func metrics(for network: NetworkModel) -> NetworkMetrics? {
        analysis.metrics(for: network.id)
    }

    // 1. Вычисляемое свойство для выбранной сети (нужно для Инспектора)
    var selectedNetwork: NetworkModel? {
        guard let selectedNetworkId else { return nil }
        return networks.first { $0.id == selectedNetworkId }
    }

    func sidebarOptions(for category: SidebarCategory) -> [(value: String, count: Int)] {
        let source = baseFilteredNetworks
        var counts: [String: Int] = [:]

        for net in source {
            let key: String
            switch category {
            case .networkName:
                key = net.displaySSID
            case .mode:
                key = net.mode
            case .channel:
                key = "\(net.channel)"
            case .channelWidth:
                key = net.channelWidthLabel
            case .security:
                key = net.security
            case .accessPoint:
                key = net.bssid.isEmpty ? "<Hidden>" : net.bssid
            case .vendor:
                key = net.vendor
            }
            counts[key, default: 0] += 1
        }

        return counts.keys
            .sorted { lhs, rhs in
                let lc = counts[lhs, default: 0]
                let rc = counts[rhs, default: 0]
                if lc != rc { return lc > rc }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { (value: $0, count: counts[$0, default: 0]) }
    }

    func clearQuickFilters() {
        quickFilterNetworkName = nil
        quickFilterMode = nil
        quickFilterChannel = nil
        quickFilterChannelWidth = nil
        quickFilterSecurity = nil
        quickFilterAccessPoint = nil
        quickFilterVendor = nil
    }

    // 2. Методы управления столбцами (нужны для ColumnSettingsView)
    func resetColumnsToDefault() {
        columnDefinitions = ColumnDefinition.defaults
        saveColumnSettings()
    }

    // 3. Публичные методы для геолокации (нужны для кнопок в UI)
    // Чтобы не обращаться к приватному locationManager из View
    func requestLocationAuthorization() {
        locationManager.requestAuthorization()
    }

    func openSystemLocationSettings() {
        locationManager.openSystemSettings()
    }

    // MARK: - Public System Hooks

    /// Вызывается из App при переходе в активное состояние,
    /// чтобы проверить, не изменил ли пользователь права доступа в Настройках
    func checkLocationAuthorization() {
        // Предполагается, что ваш класс LocationManager имеет этот метод.
        // Если это стандартный CLLocationManager, то статус обновляется автоматически через делегат,
        // но если это ваша обертка — вызываем её метод.
        locationManager.refreshAuthorizationStatus()
    }

    // MARK: - Export (Improved CSV)

    func exportCSV() {
        let visibleColumns = columnDefinitions.sorted { $0.order < $1.order }.filter { $0.isVisible }
        let headers = visibleColumns.map { "\"\($0.displayTitle)\"" }.joined(separator: ",")

        var rows: [String] = []
        for net in networks {
            let fields = visibleColumns.map { col -> String in
                let value = textForColumn(id: col.id, net: net)
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            rows.append(fields.joined(separator: ","))
        }

        // UTF-8 BOM keeps non-ASCII SSIDs intact in Excel; CRLF follows RFC 4180.
        let csvContent = "\u{FEFF}" + ([headers] + rows).joined(separator: "\r\n") + "\r\n"
        presentSavePanel(
            defaultName: "WiFA-Scan-\(Self.fileTimestamp()).csv",
            contentType: .commaSeparatedText,
            content: csvContent
        )
    }

    func exportJSON() {
        let payload: [String: Any] = [
            "generator": "WiFA",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "summary": [
                "networks": networks.count,
                "averageQuality": analysis.averageQuality,
                "criticalSecurityFindings": analysis.criticalFindingCount,
            ],
            "networks": networks.map { networkJSON($0) },
            "recommendations": WiFiBand.allCases.compactMap { band -> [String: Any]? in
                guard let best = analysis.bestChannel(for: band) else { return nil }
                return [
                    "band": band.label,
                    "channel": best.channel,
                    "widthMHz": best.widthMHz,
                    "score": best.score,
                    "overlappingNetworks": best.overlappingCount,
                    "coChannelNetworks": best.coChannelCount,
                    "dfs": best.isDFS,
                    "rationale": best.rationale,
                ]
            },
        ]

        guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            presentError("Could not encode scan results as JSON.")
            return
        }

        presentSavePanel(
            defaultName: "WiFA-Scan-\(Self.fileTimestamp()).json",
            contentType: .json,
            content: string
        )
    }

    private func networkJSON(_ network: NetworkModel) -> [String: Any] {
        var object: [String: Any] = [
            "id": network.id,
            "ssid": network.ssid,
            "bssid": network.bssid,
            "vendor": network.vendor,
            "band": network.band.label,
            "channel": network.channel,
            "widthMHz": network.channelWidthMHz,
            "generation": network.generation.label,
            "security": network.security,
            "signalDbm": network.signal,
            "noiseDbm": network.noise.map { $0 as Any } ?? NSNull(),
            "snrDb": network.snr.map { $0 as Any } ?? NSNull(),
            "channelUtilizationPercent": network.channelUtilization.map { $0 as Any } ?? NSNull(),
            "countryCode": network.countryCode.map { $0 as Any } ?? NSNull(),
            "wpsEnabled": network.wpsEnabled.map { $0 as Any } ?? NSNull(),
            "pmfRequired": network.pmfRequired.map { $0 as Any } ?? NSNull(),
            "firstSeen": network.firstSeen.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull(),
            "lastSeen": network.lastSeen.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull(),
            "informationElements": network.informationElements.map { element in
                [
                    "id": element.elementId,
                    "name": element.name,
                    "length": element.length,
                    "summary": element.summary,
                ]
            },
        ]
        if let metrics = analysis.metrics(for: network.id) {
            object["qualityScore"] = metrics.qualityScore
            object["congestionScore"] = metrics.congestionScore
            object["securityScore"] = metrics.securityScore
            object["overlappingNetworks"] = metrics.overlappingCount
            object["issues"] = metrics.issues.map {
                ["severity": $0.severity.label, "title": $0.title, "detail": $0.detail]
            }
        }
        return object
    }

    private func presentSavePanel(defaultName: String, contentType: UTType, content: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self?.presentError("Could not save the file: \(error.localizedDescription)")
            }
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export failed"
        alert.informativeText = message
        alert.runModal()
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Persistence

    func toggleColumn(_ id: String) {
        if let idx = columnDefinitions.firstIndex(where: { $0.id == id }) {
            columnDefinitions[idx].isVisible.toggle()
            saveColumnSettings()
            // Принудительно уведомляем View об изменении
            objectWillChange.send()
        }
    }

    func saveColumnSettings() {
        if let data = try? JSONEncoder().encode(columnDefinitions) {
            UserDefaults.standard.set(data, forKey: "WifiColumns_v4")
        }
    }

    private func loadColumnSettings() {
        if let data = UserDefaults.standard.data(forKey: "WifiColumns_v4"),
            let saved = try? JSONDecoder().decode([ColumnDefinition].self, from: data)
        {
            columnDefinitions = normalizeColumnDefinitions(saved)
        }
    }

    private func normalizeColumnDefinitions(_ saved: [ColumnDefinition]) -> [ColumnDefinition] {
        let sortedSaved = saved.sorted { $0.order < $1.order }
        var unique: [String: ColumnDefinition] = [:]
        for def in sortedSaved where unique[def.id] == nil {
            unique[def.id] = def
        }

        var normalized: [ColumnDefinition] = []
        var order = 0
        for def in ColumnDefinition.defaults {
            if var savedDef = unique[def.id] {
                savedDef.title = def.title
                if savedDef.width <= 0 { savedDef.width = def.width }
                savedDef.order = order
                normalized.append(savedDef)
            } else {
                var fallback = def
                fallback.order = order
                normalized.append(fallback)
            }
            order += 1
        }
        return normalized
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard

        let savedInterval = defaults.double(forKey: refreshIntervalKey)
        if savedInterval >= 0.5 { refreshInterval = savedInterval }

        if defaults.object(forKey: "Wifa.filterBand24") != nil {
            filterBand24 = defaults.bool(forKey: "Wifa.filterBand24")
        }
        if defaults.object(forKey: "Wifa.filterBand5") != nil {
            filterBand5 = defaults.bool(forKey: "Wifa.filterBand5")
        }
        if defaults.object(forKey: "Wifa.filterBand6") != nil {
            filterBand6 = defaults.bool(forKey: "Wifa.filterBand6")
        }
        if defaults.object(forKey: "Wifa.minSignal") != nil {
            minSignalThreshold = defaults.double(forKey: "Wifa.minSignal")
        }
        if let rawRemove = defaults.object(forKey: "Wifa.removeAfter") as? Double,
            let interval = NetworkRemovalInterval(rawValue: rawRemove)
        {
            removeAfterInterval = interval
        }
        if let rawUnit = defaults.string(forKey: "Wifa.signalUnit"),
            let mode = SignalDisplayMode(rawValue: rawUnit)
        {
            signalDisplayMode = mode
        }
        if defaults.object(forKey: "Wifa.highlightConnected") != nil {
            highlightConnectedNetworks = defaults.bool(forKey: "Wifa.highlightConnected")
        }
        if let sortKey = defaults.string(forKey: "Wifa.sortKey"), ColumnId(rawValue: sortKey) != nil {
            currentSortKey = sortKey
        }
        if defaults.object(forKey: "Wifa.sortAscending") != nil {
            isSortAscending = defaults.bool(forKey: "Wifa.sortAscending")
        }
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(refreshInterval, forKey: refreshIntervalKey)
        defaults.set(filterBand24, forKey: "Wifa.filterBand24")
        defaults.set(filterBand5, forKey: "Wifa.filterBand5")
        defaults.set(filterBand6, forKey: "Wifa.filterBand6")
        defaults.set(minSignalThreshold, forKey: "Wifa.minSignal")
        defaults.set(removeAfterInterval.rawValue, forKey: "Wifa.removeAfter")
        defaults.set(signalDisplayMode.rawValue, forKey: "Wifa.signalUnit")
        defaults.set(highlightConnectedNetworks, forKey: "Wifa.highlightConnected")
        if let currentSortKey {
            defaults.set(currentSortKey, forKey: "Wifa.sortKey")
        }
        defaults.set(isSortAscending, forKey: "Wifa.sortAscending")
    }

    private func maxHistoryPoints() -> Int {
        let interval = max(0.5, refreshInterval)
        let points = Int((historyWindowSeconds / interval).rounded())
        return max(20, min(300, points))
    }
}
