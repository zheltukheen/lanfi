import Foundation

/// The one catalogue of persisted preference keys.
///
/// `AppSettings` is the typed model; this enum is the wire/spelling layer that
/// every `UserDefaults`/`@AppStorage` call site uses instead of a literal, so a
/// renamed or mistyped key is a compile error and the whole key surface can be
/// audited from one file. Keys whose value is a document rather than a
/// preference (profiles, filters, saved servers) are listed too: they are still
/// key names the app persists and must not drift.
public enum AppSettingsKey: String, CaseIterable, Sendable {
    // MARK: Settings blob

    /// JSON-encoded `AppSettings`; the canonical record.
    case settingsBlob = "LanFi.settings.v1"

    // MARK: Appearance and table

    case appearance = "LanFi.appearance"
    case rowDensity = "LanFi.rowDensity"
    case highContrast = "LanFi.highContrast"
    case colorBlindSafe = "LanFi.colorBlindSafe"

    // MARK: Analyzer display

    case hideEmptyGraphs = "LanFi.hideEmptyGraphs"
    case menuBarMetric = "LanFi.menuBar.metric"
    case menuBarStyle = "LanFi.menuBar.style"
    case menuBarUnit = "LanFi.menuBar.unit"
    case graphChannel = "LanFi.graph.channel"
    case graphSecurity = "LanFi.graph.security"
    case graphOccupancy = "LanFi.graph.occupancy"
    case toolbarSearch = "LanFi.toolbar.search"
    case toolbarExport = "LanFi.toolbar.export"
    case historyChartMode = "LanFi.historyChart.mode"
    case signalUnit = "LanFi.signalUnit"
    case highlightConnected = "LanFi.highlightConnected"
    case groupMode = "LanFi.groupMode"

    // MARK: Scanning

    case scanOnLaunch = "LanFi.scanOnLaunch"
    case refreshInterval = "RefreshIntervalSeconds"
    case scanReduceInBackground = "LanFi.scan.reduceInBackground"
    case scanDwellMilliseconds = "LanFi.scan.dwellMilliseconds"
    case wifiInterface = "LanFi.wifiInterface"
    case hasCompletedFirstRun = "LanFi.hasCompletedFirstRun"

    // MARK: Analyzer filters

    case filterBand24 = "LanFi.filterBand24"
    case filterBand5 = "LanFi.filterBand5"
    case filterBand6 = "LanFi.filterBand6"
    case filterOther = "LanFi.filterOther"
    case filterWiFi7 = "LanFi.filterWiFi7"
    case minSignal = "LanFi.minSignal"
    case removeAfter = "LanFi.removeAfter"

    // MARK: Alerts

    case alertsWeakSignal = "LanFi.alerts.weakSignal"
    case alertsOpenNetwork = "LanFi.alerts.openNetwork"
    case alertsChannelChange = "LanFi.alerts.channelChange"
    case alertsLastConnectedChannel = "LanFi.alerts.lastConnectedChannel"

    // MARK: Monitor

    case monitorRecording = "LanFi.monitor.recording"
    case monitorRetention = "LanFi.monitor.retention"
    case monitorAlerts = "LanFi.monitor.alerts"

    // MARK: Capture, survey and reports

    case captureAutoWireshark = "LanFi.capture.autoWireshark"
    case captureProfiles = "LanFi.captureProfiles"
    case surveyHeatmapDetail = "LanFi.survey.heatmapDetail"
    case reportsEnabled = "LanFi.reports.enabled"
    case reportsMinutes = "LanFi.reports.minutes"
    case reportsFolder = "LanFi.reports.folder"
    case reportsFormat = "LanFi.reports.format"

    // MARK: MCP

    case mcpPublishSnapshot = "LanFi.mcp.publishSnapshot"
    case mcpClientName = "LanFi.mcp.clientName"
    case mcpCLIPath = "LanFi.mcp.cliPath"

    // MARK: Automation and toolkit preferences

    case autoUpdateOUI = "LanFi.autoUpdateOUI"
    case speedTestSchedule = "LanFi.speedTestSchedule"
    case lanGuardEnabled = "LanFi.lanGuardEnabled"
    case processTrafficEnabled = "LanFi.processTraffic.enabled"
    case iperf3Servers = "LanFi.iperf3.servers"

    // MARK: Layout and navigation state

    case showInspector = "LanFi.showInspector"
    case bottomTab = "LanFi.bottomTab"
    case tabLayoutVersion = "LanFi.tabLayoutVersion"
    case inspectorWidth = "LanFi.inspectorWidth"
    case bottomPanelHeight = "LanFi.bottomPanelHeight"
    case toolkitSelection = "LanFi.toolkit.selection"
    case toolkitTarget = "LanFi.toolkit.target"
    case toolkitTargetHistory = "LanFi.toolkit.targetHistory"
    case toolkitSidebarWidth = "LanFi.toolkit.sidebarWidth"
    case lanScannerTab = "LanFi.lanScannerTab"
    case settingsSection = "LanFi.settings.section"
    case sortKey = "LanFi.sortKey"
    case sortAscending = "LanFi.sortAscending"

    // MARK: Documents

    case wifiColumns = "WifiColumns_v4"
    case columnProfiles = "LanFi.columnProfiles"
    case customFilters = "LanFi.customFilters"
    case coloringRules = "LanFi.coloringRules"
    case workspaceProfiles = "LanFi.workspaceProfiles"
    case expressionColumns = "LanFi.expressionColumns"
    case remoteSensors = "LanFi.remoteSensors"
    case controllerAccounts = "LanFi.controllerAccounts"
    case customOUIOverrides = "LanFi.customOUIOverrides"

    /// Every key the app persists, sorted, for audits and migration tests.
    public static var allPersistedKeys: [String] {
        allCases.map(\.rawValue).sorted()
    }
}
