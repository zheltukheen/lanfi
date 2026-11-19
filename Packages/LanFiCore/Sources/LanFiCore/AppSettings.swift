import Foundation

/// Typed, versioned application preferences.
///
/// `AppSettings` is the canonical model: the JSON blob is the record of truth
/// and `AppSettingsStore` mirrors every field to its legacy `LanFi.*` key so the
/// remaining `@AppStorage` readers stay live. Fields that the older screens
/// still write straight to their legacy key are refreshed from that key before
/// a save, so a theme change never rolls back a report or MCP setting.
public struct AppSettings: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark
    }

    /// Signal column unit; raw values match `SignalDisplayMode`.
    public enum SignalUnit: String, Codable, CaseIterable, Sendable {
        case dbm = "dBm"
        case percent = "%"
    }

    /// Raw values match `NetworkGroupMode`.
    public enum GroupMode: String, Codable, CaseIterable, Sendable {
        case none
        case ssid
        case physicalAP
        case band
        case vendor
        case security
    }

    /// Raw values match `HistoryChartMode`.
    public enum HistoryChartMode: String, Codable, CaseIterable, Sendable {
        case signal
        case noise
        case both
    }

    /// Raw values match `SpeedTestSchedule`.
    public enum SpeedTestCadence: String, Codable, CaseIterable, Sendable {
        case off
        case hourly
        case everySixHours
        case daily
    }

    /// Raw values match `MonitorRetention`.
    public enum MonitorRetention: String, Codable, CaseIterable, Sendable {
        case hour
        case day
        case week
        case month
    }

    /// Raw values match the survey heatmap picker.
    public enum SurveyHeatmapDetail: String, Codable, CaseIterable, Sendable {
        case fast
        case balanced
        case high
    }

    public enum ReportFormat: String, Codable, CaseIterable, Sendable {
        case csv = "CSV"
        case pdf = "PDF"
    }

    /// Menu-bar live meter preferences (P0.6).
    public struct MenuBarMeterSettings: Codable, Equatable, Sendable {
        public enum Metric: String, Codable, CaseIterable, Sendable {
            case throughput
            case signal
            case quality
            case latency
        }

        public enum LabelStyle: String, Codable, CaseIterable, Sendable {
            case iconOnly
            case iconAndNumber
            case iconAndGraph
            case iconGraphAndNumber

            public var showsNumber: Bool {
                switch self {
                case .iconOnly, .iconAndGraph: return false
                case .iconAndNumber, .iconGraphAndNumber: return true
                }
            }

            public var showsGraph: Bool {
                switch self {
                case .iconOnly, .iconAndNumber: return false
                case .iconAndGraph, .iconGraphAndNumber: return true
                }
            }
        }

        public enum Unit: String, Codable, CaseIterable, Sendable {
            case bits
            case bytes
        }

        public var metric: Metric = .throughput
        public var labelStyle: LabelStyle = .iconAndGraph
        public var unit: Unit = .bits

        public init() {}
    }

    /// Scan bands, thresholds and passive-scan dwell.
    public struct ScanSettings: Codable, Equatable, Sendable {
        public var band24 = true
        public var band5 = true
        public var band6 = true
        public var bandOther = true
        public var wifi7 = true
        public var minSignal: Double = -100
        public var removeAfter: Double = 120
        public var highlightConnected = true
        public var reduceInBackground = true
        public var dwellMilliseconds = 150
        public var groupMode: GroupMode = .none
        public var signalUnit: SignalUnit = .dbm
        public var sortKey: String = ""
        public var sortAscending = true

        public init() {}
    }

    /// Connection alerts raised from the live scan.
    public struct AlertSettings: Codable, Equatable, Sendable {
        public var weakSignal = true
        public var openNetwork = true
        public var channelChange = true

        public init() {}
    }

    /// Persistent Wi-Fi Monitor.
    public struct MonitorSettings: Codable, Equatable, Sendable {
        public var recording = true
        public var retention: MonitorRetention = .day

        public init() {}
    }

    /// P3.3 connectivity watchdog: interval, probe endpoints and alerts.
    public struct ConnectivitySettings: Codable, Equatable, Sendable {
        public var enabled = true
        public var intervalSeconds: Double = 30
        public var primaryProbeURL = "http://captive.apple.com/hotspot-detect.html"
        public var fallbackProbeURL = "http://www.apple.com/library/test/success.html"
        public var notifyOffline = true
        public var notifyCaptivePortal = true
        public var notifyRestored = true
        public var cooldownMinutes = 5

        public init() {}
    }

    public struct CaptureSettings: Codable, Equatable, Sendable {
        public var autoOpenWireshark = false

        public init() {}
    }

    public struct SurveySettings: Codable, Equatable, Sendable {
        public var heatmapDetail: SurveyHeatmapDetail = .balanced

        public init() {}
    }

    public struct ReportSettings: Codable, Equatable, Sendable {
        public var enabled = false
        public var minutes = 15
        public var folder = ""
        public var format: ReportFormat = .csv

        public init() {}
    }

    /// Model Context Protocol hand-off.
    public struct MCPSettings: Codable, Equatable, Sendable {
        public var publishSnapshot = true
        public var clientName = "lanfi"
        public var cliPath = ""

        public init() {}
    }

    /// Schedules and tool switches that used to be separate keys.
    public struct AutomationSettings: Codable, Equatable, Sendable {
        public var speedTestCadence: SpeedTestCadence = .off
        public var lanGuardEnabled = false
        public var processTrafficEnabled = false
        public var listenerWatch = false
        /// P3.10: describe unknown services with the on-device model.
        public var serviceDescriptions = false
        /// P3.7: watch the gateway ARP entry and the resolver answer.
        public var gatewayGuard = true
        /// P3.4: show VPN state and DNS/IPv6 leak indicators.
        public var vpnGuard = true
        /// P3.8: turn Wi-Fi off while a physical Ethernet link is up.
        public var linkAutomation = false
        public var autoUpdateOUI = true

        public init() {}
    }

    public struct DisplaySettings: Codable, Equatable, Sendable {
        public var historyChartMode: HistoryChartMode = .signal
        public var colorBlindSafe = false

        public init() {}
    }

    public struct NetworkInterfaceSettings: Codable, Equatable, Sendable {
        /// Empty means "system default".
        public var preferred: String = ""

        public init() {}
    }

    /// Window and navigation state.
    public struct LayoutSettings: Codable, Equatable, Sendable {
        public var showInspector = true
        public var bottomTab = 9
        public var inspectorWidth: Double = 300
        public var bottomPanelHeight: Double = 460
        public var toolkitSelection = ""
        public var toolkitSidebarWidth: Double = 228
        public var lanScannerTab = 0
        public var settingsSection = "general"
        public var tabLayoutVersion = 5
        public var hasCompletedFirstRun = false

        public init() {}
    }

    public var appearance: Appearance = .system
    public var rowDensity: Double = 30
    public var highContrast: Bool = false
    public var hideEmptyGraphs: Bool = false
    public var showChannelRecommendations: Bool = true
    public var showSecurityAudit: Bool = true
    public var showChannelOccupancy: Bool = true
    public var toolbarSearch: Bool = true
    public var toolbarExport: Bool = true
    public var scanOnLaunch: Bool = true
    public var refreshInterval: Double = 3
    /// Optional so settings written before the meter existed still decode.
    public var menuBarMeter: MenuBarMeterSettings?

    public var scan = ScanSettings()
    public var alerts = AlertSettings()
    public var monitor = MonitorSettings()
    public var connectivity = ConnectivitySettings()
    public var capture = CaptureSettings()
    public var survey = SurveySettings()
    public var reports = ReportSettings()
    public var mcp = MCPSettings()
    public var automation = AutomationSettings()
    public var display = DisplaySettings()
    public var networkInterface = NetworkInterfaceSettings()
    public var layout = LayoutSettings()
    /// Stamped by the store from its injected clock; used by export/import.
    public var lastModified: Date?

    /// Non-optional accessor for the menu-bar meter preferences.
    public var menuBar: MenuBarMeterSettings {
        get { menuBarMeter ?? MenuBarMeterSettings() }
        set { menuBarMeter = newValue }
    }

    public init() {}

    /// `lastModified` is export metadata, so it does not take part in equality:
    /// exporting and re-importing the same settings must produce an equal value.
    public static func == (lhs: AppSettings, rhs: AppSettings) -> Bool {
        lhs.appearance == rhs.appearance
            && lhs.rowDensity == rhs.rowDensity
            && lhs.highContrast == rhs.highContrast
            && lhs.hideEmptyGraphs == rhs.hideEmptyGraphs
            && lhs.showChannelRecommendations == rhs.showChannelRecommendations
            && lhs.showSecurityAudit == rhs.showSecurityAudit
            && lhs.showChannelOccupancy == rhs.showChannelOccupancy
            && lhs.toolbarSearch == rhs.toolbarSearch
            && lhs.toolbarExport == rhs.toolbarExport
            && lhs.scanOnLaunch == rhs.scanOnLaunch
            && lhs.refreshInterval == rhs.refreshInterval
            && lhs.menuBarMeter == rhs.menuBarMeter
            && lhs.scan == rhs.scan
            && lhs.alerts == rhs.alerts
            && lhs.monitor == rhs.monitor
            && lhs.connectivity == rhs.connectivity
            && lhs.capture == rhs.capture
            && lhs.survey == rhs.survey
            && lhs.reports == rhs.reports
            && lhs.mcp == rhs.mcp
            && lhs.automation == rhs.automation
            && lhs.display == rhs.display
            && lhs.networkInterface == rhs.networkInterface
            && lhs.layout == rhs.layout
    }

    /// Tolerant decoding: sections added after a settings file was written fall
    /// back to their defaults instead of discarding the whole record.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        appearance =
            try container.decodeIfPresent(Appearance.self, forKey: .appearance)
            ?? defaults.appearance
        rowDensity = try container.decodeIfPresent(Double.self, forKey: .rowDensity) ?? 30
        highContrast = try container.decodeIfPresent(Bool.self, forKey: .highContrast) ?? false
        hideEmptyGraphs =
            try container.decodeIfPresent(Bool.self, forKey: .hideEmptyGraphs) ?? false
        showChannelRecommendations =
            try container.decodeIfPresent(Bool.self, forKey: .showChannelRecommendations) ?? true
        showSecurityAudit =
            try container.decodeIfPresent(Bool.self, forKey: .showSecurityAudit) ?? true
        showChannelOccupancy =
            try container.decodeIfPresent(Bool.self, forKey: .showChannelOccupancy) ?? true
        toolbarSearch = try container.decodeIfPresent(Bool.self, forKey: .toolbarSearch) ?? true
        toolbarExport = try container.decodeIfPresent(Bool.self, forKey: .toolbarExport) ?? true
        scanOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .scanOnLaunch) ?? true
        refreshInterval =
            try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 3
        menuBarMeter =
            try container.decodeIfPresent(MenuBarMeterSettings.self, forKey: .menuBarMeter)
        scan = try container.decodeIfPresent(ScanSettings.self, forKey: .scan) ?? ScanSettings()
        alerts =
            try container.decodeIfPresent(AlertSettings.self, forKey: .alerts) ?? AlertSettings()
        monitor =
            try container.decodeIfPresent(MonitorSettings.self, forKey: .monitor)
            ?? MonitorSettings()
        connectivity =
            try container.decodeIfPresent(ConnectivitySettings.self, forKey: .connectivity)
            ?? ConnectivitySettings()
        capture =
            try container.decodeIfPresent(CaptureSettings.self, forKey: .capture)
            ?? CaptureSettings()
        survey =
            try container.decodeIfPresent(SurveySettings.self, forKey: .survey) ?? SurveySettings()
        reports =
            try container.decodeIfPresent(ReportSettings.self, forKey: .reports)
            ?? ReportSettings()
        mcp = try container.decodeIfPresent(MCPSettings.self, forKey: .mcp) ?? MCPSettings()
        automation =
            try container.decodeIfPresent(AutomationSettings.self, forKey: .automation)
            ?? AutomationSettings()
        display =
            try container.decodeIfPresent(DisplaySettings.self, forKey: .display)
            ?? DisplaySettings()
        networkInterface =
            try container.decodeIfPresent(NetworkInterfaceSettings.self, forKey: .networkInterface)
            ?? NetworkInterfaceSettings()
        layout =
            try container.decodeIfPresent(LayoutSettings.self, forKey: .layout) ?? LayoutSettings()
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified)
    }

    /// Keeps values in the ranges the UI actually supports.
    public mutating func normalize() {
        if !(0.5...60).contains(refreshInterval) {
            refreshInterval = 3
        }
        if ![24, 30, 38].contains(rowDensity) {
            rowDensity = 30
        }
        if !(50...1000).contains(scan.dwellMilliseconds) {
            scan.dwellMilliseconds = 150
        }
        if !(-100...(-40)).contains(scan.minSignal) {
            scan.minSignal = -100
        }
        if ![60.0, 120, 300, 600].contains(scan.removeAfter) {
            scan.removeAfter = 120
        }
        if !(15...300).contains(connectivity.intervalSeconds) {
            connectivity.intervalSeconds = 30
        }
        if !(0...120).contains(connectivity.cooldownMinutes) {
            connectivity.cooldownMinutes = 5
        }
        if URL(string: connectivity.primaryProbeURL)?.scheme == nil {
            connectivity.primaryProbeURL = ConnectivitySettings().primaryProbeURL
        }
        if URL(string: connectivity.fallbackProbeURL)?.scheme == nil {
            connectivity.fallbackProbeURL = ConnectivitySettings().fallbackProbeURL
        }
        reports.minutes = max(reports.minutes, 5)
        layout.inspectorWidth = min(max(layout.inspectorWidth, 220), 520)
        layout.toolkitSidebarWidth = min(max(layout.toolkitSidebarWidth, 180), 380)
    }
}
