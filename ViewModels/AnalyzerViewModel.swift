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

enum FilterColumn: String, CaseIterable, Identifiable {
    case band
    case channel
    case channelWidth
    case security
    case mode
    case generation
    case accessPoint
    case vendor
    case countryCode
    case apName

    var id: String { rawValue }

    /// The table column this filter is derived from. SSID is deliberately
    /// excluded: a network name is searchable, not a categorical filter.
    var column: ColumnId {
        switch self {
        case .band: return .band
        case .channel: return .channel
        case .channelWidth: return .channelWidth
        case .security: return .security
        case .mode: return .mode
        case .generation: return .generation
        case .accessPoint: return .bssid
        case .vendor: return .vendor
        case .countryCode: return .countryCode
        case .apName: return .apName
        }
    }

    var title: String { column.defaultTitle }

    var systemImage: String {
        switch self {
        case .band: return "antenna.radiowaves.left.and.right"
        case .channel: return "waveform.path.ecg"
        case .channelWidth: return "arrow.left.and.right"
        case .security: return "lock.shield"
        case .mode: return "dot.radiowaves.left.and.right"
        case .generation: return "sparkles"
        case .accessPoint:
            return "antenna.radiowaves.left.and.right"
        case .vendor: return "building.2"
        case .countryCode: return "globe"
        case .apName: return "rectangle.connected.to.line.below"
        }
    }

    func value(for network: NetworkModel) -> String {
        switch self {
        case .band: return network.band.label
        case .channel: return String(network.channel)
        case .channelWidth: return network.channelWidthLabel
        case .security: return network.security
        case .mode: return network.mode
        case .generation: return network.generation.label
        case .accessPoint: return network.bssid.isEmpty ? "<Hidden>" : network.bssid
        case .vendor: return network.vendor
        case .countryCode: return network.countryCode ?? "—"
        case .apName: return network.apName ?? "—"
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
    private let customFilterStore = CustomFilterStore()
    private let coloringRuleStore = ColoringRuleStore()
    private let workspaceProfileStore = WorkspaceProfileStore()
    private let expressionColumnStore = ExpressionColumnStore()
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
    @Published var noiseHistory: [String: [Int?]] = [:]
    @Published var snrHistory: [String: [Int?]] = [:]
    @Published var utilizationHistory: [String: [Int?]] = [:]
    @Published private(set) var analysis: AnalysisReport = .empty
    @Published private(set) var annotations: [String: NetworkAnnotation] = [:]
    @Published private(set) var sessions: [ScanSession] = []
    @Published private(set) var columnProfiles: [ColumnProfile] = []
    @Published private(set) var menuBarAlerts: [MenuBarAlert] = []
    @Published private(set) var customFilters: [CustomFilter] = []
    @Published private(set) var coloringRules: [ColoringRule] = []
    @Published private(set) var workspaceProfiles: [WorkspaceProfile] = []
    @Published private(set) var expressionColumns: [ExpressionColumn] = []
    @Published var activeFilterId: String?
    @Published private(set) var loadedSession: ScanSession?
    @Published var sessionMessage: String?
    @Published private var selectedNetworkIdStorage: String? = nil
    @Published var selectedNetworkIds: Set<String> = []

    var selectedNetworkId: String? {
        get { selectedNetworkIdStorage }
        set {
            selectedNetworkIdStorage = newValue
            if let newValue {
                selectedNetworkIds = [newValue]
            } else {
                selectedNetworkIds.removeAll()
            }
        }
    }
    @Published var highlightConnectedNetworks: Bool = true { didSet { savePreferences() } }

    // Settings & Filters
    @Published var filterBand24 = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var filterBand5 = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var filterBand6 = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var filterWiFi7 = true { didSet { requestFilterUpdate(); savePreferences() } }
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
    @Published private(set) var quickFilters: [FilterColumn: Set<String>] = [:]

    @Published var isLocationAuthorized = false
    @Published var errorMessage: String?
    @Published private(set) var lastScanDate: Date?

    // MARK: - Initialization
    init() {
        setupBindings()
        annotations = annotationStore.annotations
        sessions = sessionStore.sessions()
        columnProfiles = columnProfileStore.profiles()
        customFilters = customFilterStore.load()
        coloringRules = coloringRuleStore.load()
        workspaceProfiles = workspaceProfileStore.load()
        expressionColumns = expressionColumnStore.load()
        appendExpressionColumnDefinitions()
        loadPreferences()
        loadColumnSettings()
        // Стартуем сканирование сразу, но реальные данные пойдут только после разрешения Location
        startScanningLoop()
        configureScheduledReports()
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
            noiseHistory.removeValue(forKey: key)
            snrHistory.removeValue(forKey: key)
            utilizationHistory.removeValue(forKey: key)
        }

        analysis = NetworkAnalyzer.analyze(networks: Array(persistentNetworks.values))
        applyFilters()
        refreshMenuBarAlerts()
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

        var noise = noiseHistory[net.id] ?? []
        noise.append(net.noise)
        if noise.count > maxPoints { noise.removeFirst(noise.count - maxPoints) }
        noiseHistory[net.id] = noise

        var snr = snrHistory[net.id] ?? []
        snr.append(net.snr)
        if snr.count > maxPoints { snr.removeFirst(snr.count - maxPoints) }
        snrHistory[net.id] = snr

        var utilization = utilizationHistory[net.id] ?? []
        utilization.append(net.channelUtilization)
        if utilization.count > maxPoints { utilization.removeFirst(utilization.count - maxPoints) }
        utilizationHistory[net.id] = utilization
    }

    // MARK: - Filtering & Sorting

    private var scheduledReportTimer: Timer?

    func configureScheduledReports() {
        scheduledReportTimer?.invalidate()
        scheduledReportTimer = nil
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "Wifa.reports.enabled"),
            let folder = defaults.string(forKey: "Wifa.reports.folder"),
            !folder.isEmpty
        else { return }
        let minutes = max(defaults.integer(forKey: "Wifa.reports.minutes"), 5)
        scheduledReportTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.writeScheduledReport() }
        }
    }

    func writeScheduledReport() {
        let defaults = UserDefaults.standard
        guard let folder = defaults.string(forKey: "Wifa.reports.folder"), !folder.isEmpty else { return }
        let format = defaults.string(forKey: "Wifa.reports.format") ?? "CSV"
        let ext = format == "PDF" ? "pdf" : "csv"
        let url = URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent("LanFi-Report-\(Self.fileTimestamp()).\(ext)")
        if format == "PDF" {
            let data = ScanReportExporter.makePDF(
                title: "LanFi scan report", networks: networks, columns: columnDefinitions
            ) { [weak self] id, network in
                self?.textForColumn(id: id, net: network) ?? ""
            }
            try? data.write(to: url, options: .atomic)
        } else {
            try? csvContent(for: networks).write(to: url, atomically: true, encoding: .utf8)
        }
        sessionMessage = "Scheduled report saved: \(url.lastPathComponent)"
    }

    private func csvContent(for networks: [NetworkModel]) -> String {
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
        return "\u{FEFF}" + ([headers] + rows).joined(separator: "\r\n") + "\r\n"
    }

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
            if !filterWiFi7 && net.generation == .mode11be { return false }
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
        for (filter, values) in quickFilters where !values.isEmpty {
            baseFiltered = baseFiltered.filter { values.contains(filter.value(for: $0)) }
        }
        if let activeFilter {
            baseFiltered = baseFiltered.filter {
                activeFilter.matches(
                    $0,
                    metrics: analysis.metrics(for: $0.id),
                    connectedBSSID: currentConnectedBSSID
                )
            }
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
        if id.hasPrefix("expr:"),
            let uuid = UUID(uuidString: String(id.dropFirst(5))),
            let expression = expressionColumns.first(where: { $0.id == uuid })
        {
            return ExpressionEvaluator.evaluate(
                expression.template, network: net, metrics: analysis.metrics(for: net.id)
            )
        }
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

    func applyBulkAnnotation(alias: String, notes: String, to ids: Set<String>) {
        for id in ids {
            var annotation = annotationStore.annotation(for: id)
            annotation.alias = alias
            annotation.notes = notes
            annotationStore.update(annotation, for: id)
        }
        annotations = annotationStore.annotations
    }

    func rowColor(for network: NetworkModel) -> NSColor? {
        if let custom = ColorHex.color(from: annotation(for: network).colorHex ?? "") {
            return custom
        }
        for rule in coloringRules where rule.isEnabled {
            let filterRule = NetworkFilterRule(field: rule.field, op: rule.op, value: rule.value)
            if NetworkFilterEngine.evaluate(
                filterRule, network: network,
                metrics: analysis.metrics(for: network.id),
                connectedBSSID: currentConnectedBSSID
            ), let color = ColorHex.color(from: rule.colorHex) {
                return color
            }
        }
        return nil
    }

    func setNetworkColor(_ hex: String, for network: NetworkModel) {
        var annotation = annotation(for: network)
        annotation.colorHex = hex
        updateAnnotation(annotation, for: network)
    }

    func addExpressionColumn(name: String, template: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        expressionColumns.append(ExpressionColumn(id: UUID(), name: trimmed, template: template))
        expressionColumnStore.save(expressionColumns)
        appendExpressionColumnDefinitions()
    }

    func updateExpressionColumn(_ column: ExpressionColumn) {
        guard let index = expressionColumns.firstIndex(where: { $0.id == column.id }) else { return }
        expressionColumns[index] = column
        expressionColumnStore.save(expressionColumns)
        appendExpressionColumnDefinitions()
    }

    func deleteExpressionColumn(_ column: ExpressionColumn) {
        expressionColumns.removeAll { $0.id == column.id }
        expressionColumnStore.save(expressionColumns)
        columnDefinitions.removeAll { $0.id == "expr:\(column.id.uuidString)" }
        saveColumnSettings()
        objectWillChange.send()
    }

    private func appendExpressionColumnDefinitions() {
        columnDefinitions.removeAll { $0.id.hasPrefix("expr:") }
        var order = (columnDefinitions.map(\.order).max() ?? 0) + 1
        for expression in expressionColumns {
            columnDefinitions.append(
                ColumnDefinition(
                    id: "expr:\(expression.id.uuidString)",
                    title: expression.name,
                    width: 180,
                    isVisible: true,
                    order: order
                )
            )
            order += 1
        }
        saveColumnSettings()
    }

    func saveWorkspaceProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = WorkspaceProfile.new(
            name: trimmed,
            filter: currentFilterProfile(name: trimmed),
            columns: columnDefinitions,
            coloringRules: coloringRules,
            customFilters: customFilters,
            activeFilterId: activeFilterId
        )
        if let index = workspaceProfiles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            var updated = profile
            updated = WorkspaceProfile(
                id: workspaceProfiles[index].id, name: trimmed, filter: profile.filter,
                columns: profile.columns, coloringRules: profile.coloringRules,
                customFilters: profile.customFilters, activeFilterId: profile.activeFilterId,
                createdAt: workspaceProfiles[index].createdAt
            )
            workspaceProfiles[index] = updated
        } else {
            workspaceProfiles.append(profile)
        }
        workspaceProfileStore.save(workspaceProfiles)
    }

    func applyWorkspaceProfile(_ profile: WorkspaceProfile) {
        applyFilterProfile(profile.filter)
        columnDefinitions = normalizeColumnDefinitions(profile.columns)
        saveColumnSettings()
        coloringRules = profile.coloringRules
        coloringRuleStore.save(profile.coloringRules)
        customFilters = profile.customFilters
        customFilterStore.save(profile.customFilters)
        activeFilterId = profile.activeFilterId
        applyFilters()
        objectWillChange.send()
    }

    func deleteWorkspaceProfile(_ profile: WorkspaceProfile) {
        workspaceProfiles.removeAll { $0.id == profile.id }
        workspaceProfileStore.save(workspaceProfiles)
    }

    func promptSaveWorkspaceProfile() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.stringValue = "Workspace"
        let alert = NSAlert()
        alert.messageText = "Save workspace profile"
        alert.informativeText = "Save filters, bands, columns, coloring rules and custom filters."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            saveWorkspaceProfile(named: field.stringValue)
        }
    }

    func saveColoringRules(_ rules: [ColoringRule]) {
        coloringRules = rules
        coloringRuleStore.save(rules)
        objectWillChange.send()
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
        refreshMenuBarAlerts()
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

    func sidebarOptions(for filter: FilterColumn) -> [(value: String, count: Int)] {
        let source = baseFilteredNetworks
        var counts: [String: Int] = [:]
        for net in source {
            counts[filter.value(for: net), default: 0] += 1
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

    func filterSelection(for filter: FilterColumn) -> Set<String> {
        quickFilters[filter] ?? []
    }

    func setFilterSelection(_ values: Set<String>, for filter: FilterColumn) {
        if values.isEmpty {
            quickFilters.removeValue(forKey: filter)
        } else {
            quickFilters[filter] = values
        }
        requestFilterUpdate()
    }

    var totalNetworkCount: Int { persistentNetworks.count }

    var hasActiveFilters: Bool {
        !searchText.isEmpty
            || !filterBand24 || !filterBand5 || !filterBand6 || !filterWiFi7
            || minSignalThreshold > -100
            || !quickFilters.isEmpty
            || activeFilterId != nil
    }

    func clearAllFilters() {
        searchText = ""
        filterBand24 = true
        filterBand5 = true
        filterBand6 = true
        filterWiFi7 = true
        minSignalThreshold = -100
        clearQuickFilters()
    }

    func clearQuickFilters() {
        quickFilters.removeAll()
        activeFilterId = nil
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
        exportCSV(networks: networks, suffix: "scan")
    }

    func exportCSV(networks: [NetworkModel], suffix: String) {
        presentSavePanel(
            defaultName: "LanFi-\(suffix)-\(Self.fileTimestamp()).csv",
            contentType: .commaSeparatedText,
            content: csvContent(for: networks)
        )
    }

    func exportJSON() {
        exportJSON(networks: networks, suffix: "scan")
    }

    func exportJSON(networks: [NetworkModel], suffix: String) {
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
            defaultName: "LanFi-\(suffix)-\(Self.fileTimestamp()).json",
            contentType: .json,
            content: string
        )
    }

    private func refreshMenuBarAlerts() {
        let defaults = UserDefaults.standard
        let weak = defaults.object(forKey: "Wifa.alerts.weakSignal") as? Bool ?? true
        let open = defaults.object(forKey: "Wifa.alerts.openNetwork") as? Bool ?? true
        let channel = defaults.object(forKey: "Wifa.alerts.channelChange") as? Bool ?? true
        let previous = defaults.object(forKey: "Wifa.alerts.lastConnectedChannel") as? Int
        menuBarAlerts = MenuBarAlertEngine.compute(
            networks: networks,
            connectedBSSID: currentConnectedBSSID,
            weakSignalEnabled: weak,
            openNetworkEnabled: open,
            channelChangeEnabled: channel,
            previousChannel: previous
        )
        if let connected = networks.first(where: { $0.bssid == currentConnectedBSSID }) {
            defaults.set(connected.channel, forKey: "Wifa.alerts.lastConnectedChannel")
        }
    }

    var allFilters: [CustomFilter] {
        CustomFilter.automatic + customFilters
    }

    var activeFilter: CustomFilter? {
        guard let activeFilterId else { return nil }
        return allFilters.first { $0.id == activeFilterId }
    }

    func setActiveFilter(_ filter: CustomFilter?) {
        activeFilterId = filter?.id
        applyFilters()
    }

    func saveCustomFilter(_ filter: CustomFilter) {
        if let index = customFilters.firstIndex(where: { $0.id == filter.id }) {
            customFilters[index] = filter
        } else {
            customFilters.append(filter)
        }
        customFilterStore.save(customFilters)
        if activeFilterId == filter.id { applyFilters() }
    }

    func deleteCustomFilter(_ filter: CustomFilter) {
        customFilters.removeAll { $0.id == filter.id }
        if activeFilterId == filter.id { activeFilterId = nil }
        customFilterStore.save(customFilters)
        applyFilters()
    }

    var selectedNetworks: [NetworkModel] {
        let ids = selectedNetworkIds
        if ids.isEmpty, let selectedNetwork {
            return [selectedNetwork]
        }
        return networks.filter { ids.contains($0.id) }
    }

    func setSelection(ids: Set<String>, primary: String?) {
        selectedNetworkIds = ids
        selectedNetworkIdStorage = primary ?? ids.first
    }

    func copySelectedNetworks() {
        let lines = selectedNetworks.map { "\($0.displaySSID) · \($0.bssid)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func exportSelectedCSV() {
        exportCSV(networks: selectedNetworks, suffix: "selection")
    }

    func exportSelectedJSON() {
        exportJSON(networks: selectedNetworks, suffix: "selection")
    }

    func currentFilterProfile(name: String = "LanFi filter") -> FilterProfile {
        FilterProfile.capture(
            name: name, searchText: searchText,
            band24: filterBand24, band5: filterBand5, band6: filterBand6,
            wifi7: filterWiFi7,
            minSignal: minSignalThreshold, groupMode: groupMode,
            signalUnit: signalDisplayMode
        )
    }

    func applyFilterProfile(_ profile: FilterProfile) {
        searchText = profile.searchText
        filterBand24 = profile.band24
        filterBand5 = profile.band5
        filterBand6 = profile.band6
        filterWiFi7 = profile.wifi7 ?? true
        minSignalThreshold = profile.minSignal
        if let mode = NetworkGroupMode(rawValue: profile.groupMode) {
            groupMode = mode
        }
        if let unit = SignalDisplayMode(rawValue: profile.signalUnit) {
            signalDisplayMode = unit
        }
    }

    func exportFilterProfile() {
        let panel = NSSavePanel()
        panel.title = "Export filter profile"
        panel.nameFieldStringValue = "LanFi-Filter.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(currentFilterProfile()) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func importExternalScan() {
        let panel = NSOpenPanel()
        panel.title = "Import scan"
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let networks = try GenericScanImporter.load(url)
            guard !networks.isEmpty else {
                presentError("The import contained no usable networks.")
                return
            }
            let session = ScanSession(
                id: UUID(), name: "Imported \(url.lastPathComponent)",
                createdAt: Date(), networks: networks, annotations: annotations
            )
            loadSession(session)
        } catch {
            presentError("Import failed: \(error.localizedDescription)")
        }
    }

    func promptImportExternalScanURL() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 22))
        field.placeholderString = "https://example.com/scan.json"
        let alert = NSAlert()
        alert.messageText = "Import scan from URL"
        alert.informativeText = "Fetch a LanFi JSON export or a CSV scan from an HTTP(S) endpoint."
        alert.accessoryView = field
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme,
            scheme == "https" || scheme == "http"
        else {
            presentError("Enter a valid HTTP(S) URL.")
            return
        }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(
                        domain: "LanFi.Import", code: http.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"
                        ])
                }
                let networks = try GenericScanImporter.load(
                    data: data, filename: url.lastPathComponent.isEmpty ? "scan.json" : url.lastPathComponent
                )
                guard !networks.isEmpty else {
                    presentError("The import contained no usable networks.")
                    return
                }
                loadSession(
                    ScanSession(
                        id: UUID(), name: "Imported \(url.host ?? "remote")",
                        createdAt: Date(), networks: networks, annotations: annotations
                    )
                )
            } catch {
                presentError("Import failed: \(error.localizedDescription)")
            }
        }
    }

    func importFilterProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import filter profile"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url),
            let profile = try? JSONDecoder().decode(FilterProfile.self, from: data)
        else {
            presentError("Could not decode the filter profile.")
            return
        }
        applyFilterProfile(profile)
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

    func exportPCAPNG() {
        guard !networks.isEmpty else {
            presentError("There are no visible networks to export.")
            return
        }
        let data = PcapExporter.makePcapngCapture(networks: networks)
        presentSaveData(
            defaultName: "LanFi-Scan-\(Self.fileTimestamp()).pcapng",
            contentType: UTType(filenameExtension: "pcapng") ?? .data,
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
        for def in sortedSaved where def.id.hasPrefix("expr:") && unique[def.id] != nil {
            var expression = def
            expression.order = order
            normalized.append(expression)
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
        if defaults.object(forKey: "Wifa.filterWiFi7") != nil {
            filterWiFi7 = defaults.bool(forKey: "Wifa.filterWiFi7")
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
        defaults.set(filterWiFi7, forKey: "Wifa.filterWiFi7")
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
