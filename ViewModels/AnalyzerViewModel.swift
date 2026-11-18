//  AnalyzerViewModel.swift

import Foundation
import Combine
import CoreWLAN
import LanFiCore
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

struct FilterColumn: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

// MARK: - ViewModel

// @MainActor гарантирует, что все обновления @Published идут в UI-потоке.
// Это решает проблему "Publishing changes from within view updates".
@MainActor
class AnalyzerViewModel: ObservableObject {

    // MARK: - Dependencies
    let scanner: any WiFiScanning
    let locationManager = LocationManager()
    let annotationStore = AnnotationStore()
    let sessionStore = SessionStore()
    let columnProfileStore = ColumnProfileStore()
    let customFilterStore = CustomFilterStore()
    let coloringRuleStore = ColoringRuleStore()
    let workspaceProfileStore = WorkspaceProfileStore()
    let expressionColumnStore = ExpressionColumnStore()
    let monitor = MonitorViewModel()
    /// P0.2 scan modes: active, passive and directed listening.
    let passiveScan = PassiveScanViewModel()
    let refreshIntervalKey = AppSettingsKey.refreshInterval.rawValue
    let historyWindowSeconds: TimeInterval = 180

    // MARK: - Internal State
    var persistentNetworks: [String: NetworkModel] = [:]
    var timer: Timer?
    var cancellables = Set<AnyCancellable>()
    var isScanning = false
    #if DEBUG
        /// Snapshot harness only: blocks live scans and Location updates so the
        /// seeded fixtures stay exactly as captured.
        var isDemoSeeded = false
    #endif
    var isAppActive = true
    var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    static let backgroundScanKey = AppSettingsKey.scanReduceInBackground.rawValue

    /// When true the auto-refresh timer keeps running but skips scans, so
    /// the table stays frozen without tearing down the scanning loop.
    @Published var isAutoScanPaused = false

    // MARK: - Color Logic

    /// Глобальный генератор цвета для сети, чтобы во всех графах он был одинаковым
    func colorFor(networkId: String) -> Color {
        let hash = stableHash(networkId)
        // hue: 0.0 ... 1.0
        let hue = Double(hash % 1000) / 1000.0
        // Высокая яркость и насыщенность для темного фона
        return Color(hue: hue, saturation: 0.85, brightness: 1.0)
    }

    func stableHash(_ input: String) -> UInt64 {
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
    @Published var history = NetworkHistory()

    var signalHistory: [String: [Int]] { history.signal }

    /// Noise samples aligned with `signalHistory`; `nil` where CoreWLAN did not
    /// report a noise floor for that scan.
    var noiseHistory: [String: [Int?]] { history.noise }

    /// Other radios of the same physical access point, inferred when the AP does
    /// not advertise an AP name.
    func coLocatedSiblings(for network: NetworkModel) -> [NetworkModel] {
        CoLocatedAPDetector.coLocatedSiblings(of: network, in: networks)
    }

    var snrHistory: [String: [Int?]] { history.snr }
    var utilizationHistory: [String: [Int?]] { history.utilization }
    @Published var analysis: AnalysisReport = .empty
    @Published var annotations: [String: NetworkAnnotation] = [:]
    @Published var sessions: [ScanSession] = []
    @Published var columnProfiles: [ColumnProfile] = []
    @Published var menuBarAlerts: [MenuBarAlert] = []
    @Published var customFilters: [CustomFilter] = []
    @Published var coloringRules: [ColoringRule] = []
    @Published var workspaceProfiles: [WorkspaceProfile] = []
    @Published var expressionColumns: [ExpressionColumn] = []
    @Published var activeFilterId: String?
    @Published var loadedSession: ScanSession?
    @Published var sessionMessage: String?
    @Published var selectedNetworkIdStorage: String? = nil
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
    @Published var filterOther = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var filterWiFi7 = true { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var minSignalThreshold: Double = -100 { didSet { requestFilterUpdate(); savePreferences() } }
    @Published var searchText: String = ""
    @Published var supportedChannels: [SupportedChannel] = []  // Обрабатывается через debounce в init

    @Published var removeAfterInterval: NetworkRemovalInterval = .twoMinutes {
        didSet { requestFilterUpdate(); savePreferences() }
    }
    @Published var signalDisplayMode: SignalDisplayMode = .dbm { didSet { savePreferences() } }

    @Published var refreshInterval: Double = 3.0
    @Published var isSortAscending: Bool = false { didSet { applyFilters(); savePreferences() } }
    @Published var currentSortKey: String? = ColumnId.signal.rawValue { didSet { applyFilters(); savePreferences() } }
    @Published var groupMode: NetworkGroupMode = .none { didSet { applyFilters(); savePreferences() } }
    @Published var tableRows: [NetworkTableRow] = []
    @Published var columnDefinitions: [ColumnDefinition] = ColumnDefinition.defaults

    // Quick filters (sidebar)
    @Published var quickFilters: [String: Set<String>] = [:]

    @Published var isLocationAuthorized = false
    @Published var errorMessage: String?
    @Published var lastScanDate: Date?
    /// Why the last scan has (or has not) usable rows; drives the workspace banner.
    @Published var scanHealth: ScanHealth = .healthy

    // MARK: - Initialization
    init(scanner: any WiFiScanning = WiFiScanner()) {
        self.scanner = scanner
        setupBindings()
        passiveScan.onNetworks = { [weak self] networks in
            self?.ingestPassiveNetworks(networks)
        }
        annotations = annotationStore.annotations
        sessions = sessionStore.sessions()
        columnProfiles = columnProfileStore.profiles()
        customFilters = customFilterStore.load()
        coloringRules = coloringRuleStore.load()
        workspaceProfiles = workspaceProfileStore.load()
        expressionColumns = expressionColumnStore.load()
        appendExpressionColumnDefinitions()
        supportedChannels = SpectrumCapabilities.current()
        loadPreferences()
        loadColumnSettings()
        // Стартуем сканирование сразу, но реальные данные пойдут только после разрешения Location
        if UserDefaults.standard.object(forKey: AppSettingsKey.scanOnLaunch.rawValue) as? Bool ?? true {
            startScanningLoop()
        }
        configureScheduledReports()
    }

    func setAppActive(_ active: Bool) {
        guard isAppActive != active else { return }
        isAppActive = active
        refreshScanCadence()
    }

    func setLowPowerMode(_ enabled: Bool) {
        guard isLowPowerMode != enabled else { return }
        isLowPowerMode = enabled
        refreshScanCadence()
    }

    func setupBindings() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.setAppActive(true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.setAppActive(false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                self?.setLowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
            .store(in: &cancellables)

        // Location Status Binding
        locationManager.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                let authorized = (status == .authorizedAlways || status == .authorized)
                #if DEBUG
                    if self.isDemoSeeded { return }
                #endif
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

    // MARK: - Report timer and MCP stamp
    var scheduledReportTimer: Timer?
    var lastMCPSnapshotDate = Date.distantPast

    // MARK: - Public System Hooks

    /// Вызывается из App при переходе в активное состояние,
    /// чтобы проверить, не изменил ли пользователь права доступа в Настройках
    func checkLocationAuthorization() {
        // Предполагается, что ваш класс LocationManager имеет этот метод.
        // Если это стандартный CLLocationManager, то статус обновляется автоматически через делегат,
        // но если это ваша обертка — вызываем её метод.
        locationManager.refreshAuthorizationStatus()
    }

}
