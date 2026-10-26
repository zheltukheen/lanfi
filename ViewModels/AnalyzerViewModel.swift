//  AnalyzerViewModel.swift

import Foundation
import Combine
import CoreWLAN
import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

// MARK: - Enums & Settings

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
    private let annotationStore = AnnotationStore()
    private let sessionStore = SessionStore()
    private let columnProfileStore = ColumnProfileStore()
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
    @Published private(set) var annotations: [String: NetworkAnnotation] = [:]
    @Published private(set) var sessions: [ScanSession] = []
    @Published private(set) var columnProfiles: [ColumnProfile] = []
    @Published private(set) var loadedSession: ScanSession?
    @Published var sessionMessage: String?
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
    @Published var groupMode: NetworkGroupMode = .none { didSet { applyFilters(); savePreferences() } }
    @Published private(set) var tableRows: [NetworkTableRow] = []
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
        annotations = annotationStore.annotations
        sessions = sessionStore.sessions()
        columnProfiles = columnProfileStore.profiles()
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
        if loadedSession == nil {
            startScanningLoop()
        }
    }

    // MARK: - Refresh Logic (Async/Await)

    func refresh() {
        guard !isScanning, loadedSession == nil else { return }
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
            apName: net.apName,
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
                let formatter = columnFormatter
                let forward = formatter.compare(p1, p2, by: key)
                let backward = formatter.compare(p2, p1, by: key)
                if !forward && !backward { return p1.id < p2.id }
                return isSortAscending ? forward : backward
            }
        }

        self.networks = filtered
        self.tableRows = NetworkGrouper.rows(
            for: filtered,
            mode: groupMode,
            metricsByNetworkId: analysis.metricsByNetworkId,
            annotationsByNetworkId: annotations
        )
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
        NetworkColumnFormatter.formatSignal(dbm, mode: signalDisplayMode)
    }

    func textForColumn(id: String, net: NetworkModel) -> String {
        guard let column = ColumnId(rawValue: id) else { return "-" }
        return columnFormatter.text(for: column, network: net)
    }

    private var columnFormatter: NetworkColumnFormatter {
        NetworkColumnFormatter(
            signalDisplayMode: signalDisplayMode,
            connectedBSSID: currentConnectedBSSID,
            metricsByNetworkId: analysis.metricsByNetworkId,
            annotationsByNetworkId: annotations
        )
    }

    func metrics(for network: NetworkModel) -> NetworkMetrics? {
        analysis.metrics(for: network.id)
    }

    func annotation(for network: NetworkModel) -> NetworkAnnotation {
        annotationStore.annotation(for: network.id)
    }

    func updateAnnotation(_ annotation: NetworkAnnotation, for network: NetworkModel) {
        annotationStore.update(annotation, for: network.id)
        annotations = annotationStore.annotations
        applyFilters()
    }

    var connectedNetwork: NetworkModel? {
        guard let bssid = currentConnectedBSSID else { return nil }
        return networks.first { $0.bssid == bssid }
    }

    func displayName(for network: NetworkModel) -> String {
        annotation(for: network).displayAlias ?? network.displaySSID
    }

    // MARK: - Sessions

    var isSessionMode: Bool { loadedSession != nil }

    @discardableResult
    func saveSession(named name: String) -> Bool {
        guard !persistentNetworks.isEmpty else {
            presentError("There are no scan results to save yet.")
            return false
        }
        do {
            let session = try sessionStore.save(
                name: name,
                networks: persistentNetworks.values.sorted { $0.displaySSID < $1.displaySSID },
                annotations: annotations
            )
            sessions = sessionStore.sessions()
            sessionMessage = "Saved session “\(session.displayName)”"
            return true
        } catch {
            presentError("Could not save the session: \(error.localizedDescription)")
            return false
        }
    }

    func loadSession(_ session: ScanSession) {
        timer?.invalidate()
        timer = nil
        loadedSession = session
        persistentNetworks = Dictionary(uniqueKeysWithValues: session.networks.map { ($0.id, $0) })
        annotations = session.annotations
        annotationStore.replaceAll(session.annotations)
        signalHistory = [:]
        selectedNetworkId = nil
        analysis = NetworkAnalyzer.analyze(networks: session.networks)
        sessionMessage = "Session “\(session.displayName)” · \(session.networkCount) networks"
        applyFilters()
    }

    func resumeLiveScan() {
        guard loadedSession != nil else { return }
        loadedSession = nil
        sessionMessage = nil
        persistentNetworks.removeAll()
        analysis = .empty
        applyFilters()
        startScanningLoop()
        refresh()
    }

    func deleteSession(_ session: ScanSession) {
        sessionStore.delete(session)
        sessions = sessionStore.sessions()
    }

    func promptSaveSession() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = "Scan \(Date().formatted(date: .abbreviated, time: .shortened))"
        let alert = NSAlert()
        alert.messageText = "Save scan session"
        alert.informativeText = "Sessions are stored locally and can be reopened without scanning."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = saveSession(named: field.stringValue)
        }
    }

    func promptOpenSession() {
        sessions = sessionStore.sessions()
        guard !sessions.isEmpty else {
            presentError("No saved sessions yet. Use Data → Save Session first.")
            return
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        for session in sessions {
            popup.addItem(withTitle: "\(session.displayName) · \(session.networkCount) networks")
        }
        let alert = NSAlert()
        alert.messageText = "Open scan session"
        alert.informativeText = "Live scanning pauses while a saved session is open."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let index = popup.indexOfSelectedItem
            guard sessions.indices.contains(index) else { return }
            loadSession(sessions[index])
        }
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

    var totalNetworkCount: Int { persistentNetworks.count }

    var hasActiveFilters: Bool {
        !searchText.isEmpty
            || !filterBand24 || !filterBand5 || !filterBand6
            || minSignalThreshold > -100
            || quickFilterNetworkName != nil
            || quickFilterMode != nil
            || quickFilterChannel != nil
            || quickFilterChannelWidth != nil
            || quickFilterSecurity != nil
            || quickFilterAccessPoint != nil
            || quickFilterVendor != nil
    }

    func clearAllFilters() {
        searchText = ""
        filterBand24 = true
        filterBand5 = true
        filterBand6 = true
        minSignalThreshold = -100
        clearQuickFilters()
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

    func applyColumnProfile(_ profile: ColumnProfile) {
        columnDefinitions = normalizeColumnDefinitions(profile.columns)
        saveColumnSettings()
        objectWillChange.send()
    }

    func saveCurrentColumnsAsProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = columnProfiles.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            columnProfiles[index].columns = columnDefinitions
        } else {
            columnProfiles.append(.new(name: trimmed, columns: columnDefinitions))
        }
        columnProfileStore.save(columnProfiles)
    }

    func deleteColumnProfile(_ profile: ColumnProfile) {
        columnProfiles.removeAll { $0.id == profile.id }
        columnProfileStore.save(columnProfiles)
    }

    func promptSaveColumnProfile() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = "My layout"
        let alert = NSAlert()
        alert.messageText = "Save column profile"
        alert.informativeText = "Store the current column order, widths and visibility."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            saveCurrentColumnsAsProfile(named: field.stringValue)
        }
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
            defaultName: "LanFi-Scan-\(Self.fileTimestamp()).csv",
            contentType: .commaSeparatedText,
            content: csvContent
        )
    }

    func exportJSON() {
        let payload: [String: Any] = [
            "generator": "LanFi",
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
            defaultName: "LanFi-Scan-\(Self.fileTimestamp()).json",
            contentType: .json,
            content: string
        )
    }

    func exportPCAP() {
        guard !networks.isEmpty else {
            presentError("There are no visible networks to export.")
            return
        }
        let data = PcapExporter.makeCapture(networks: networks)
        presentSaveData(
            defaultName: "LanFi-Scan-\(Self.fileTimestamp()).pcap",
            contentType: UTType(filenameExtension: "pcap") ?? .data,
            data: data
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

    private func presentSaveData(defaultName: String, contentType: UTType, data: Data) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self?.presentError("Could not save the capture: \(error.localizedDescription)")
            }
        }
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
        if let rawGroup = defaults.string(forKey: "Wifa.groupMode"),
            let mode = NetworkGroupMode(rawValue: rawGroup)
        {
            groupMode = mode
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
        defaults.set(groupMode.rawValue, forKey: "Wifa.groupMode")
    }

    private func maxHistoryPoints() -> Int {
        let interval = max(0.5, refreshInterval)
        let points = Int((historyWindowSeconds / interval).rounded())
        return max(20, min(300, points))
    }
}
