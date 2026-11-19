import Foundation

public enum AppSettingsError: Error, Equatable {
    case invalidData
}

/// Loads, migrates, exports and persists `AppSettings`.
///
/// The JSON blob is canonical. Two kinds of keys exist:
///
/// - keys this store owns (`appearance`, density, graphs, toolbar, scan-on-
///   launch, refresh interval, menu-bar meter) — the model wins and the legacy
///   key is a mirror the older `@AppStorage` readers observe;
/// - keys an older screen still writes directly (monitor, capture, survey,
///   reports, alerts, MCP, layout, automation) — those values are read back from
///   their key before every save, so a save from General Settings cannot roll
///   back a setting the user just changed elsewhere.
public final class AppSettingsStore: @unchecked Sendable {
    public static let shared = AppSettingsStore()

    private let lock = NSLock()
    private var stored: AppSettings

    private let storage: any SettingsStorage
    private let clock: any Clock
    private let notifications: any NotificationPosting
    private let files: any FileStoring
    private let storageKey = AppSettingsKey.settingsBlob.rawValue

    public var settings: AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(storage: UserDefaultsSettingsStorage(defaults: defaults))
    }

    public init(
        storage: any SettingsStorage,
        clock: any Clock = SystemClock(),
        notifications: any NotificationPosting = NotificationCenterPoster(),
        files: any FileStoring = FileStore()
    ) {
        self.storage = storage
        self.clock = clock
        self.notifications = notifications
        self.files = files
        stored = Self.load(
            storage: storage, storageKey: AppSettingsKey.settingsBlob.rawValue)
    }

    // MARK: - Persistence

    /// Saves the model. Legacy-owned values are refreshed from their keys first
    /// so direct writers are never rolled back.
    public func save(_ newSettings: AppSettings) {
        save(newSettings, refreshingLegacyOwned: true)
    }

    public func save(_ newSettings: AppSettings, refreshingLegacyOwned: Bool) {
        var normalized = newSettings
        if refreshingLegacyOwned {
            Self.readLegacyOwned(into: &normalized, storage: storage)
        }
        normalized.normalize()
        lock.lock()
        stored = normalized
        lock.unlock()

        if let data = try? JSONEncoder().encode(normalized) {
            storage.set(data, forKey: storageKey)
        }
        Self.writeLegacy(normalized, storage: storage)
        Self.writeLegacyOwned(normalized, storage: storage)
        notifications.post(.lanFiSettingsDidChange, userInfo: nil)
    }

    public func reset() {
        storage.removeObject(forKey: storageKey)
        var fresh = AppSettings()
        fresh.lastModified = clock.now
        lock.lock()
        stored = fresh
        lock.unlock()
        Self.writeLegacy(fresh, storage: storage)
        Self.writeLegacyOwned(fresh, storage: storage)
        notifications.post(.lanFiSettingsDidChange, userInfo: nil)
    }

    // MARK: - Export and import

    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var snapshot = settings
        snapshot.lastModified = clock.now
        return try encoder.encode(snapshot)
    }

    public func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(AppSettings.self, from: data) else {
            throw AppSettingsError.invalidData
        }
        // An import is authoritative: it overwrites legacy-owned keys too.
        save(decoded, refreshingLegacyOwned: false)
    }

    public func export(to url: URL) throws {
        try files.write(exportData(), to: url)
    }

    public func importSettings(from url: URL) throws {
        try importData(files.read(from: url))
    }

    // MARK: - Loading

    private static func load(storage: any SettingsStorage, storageKey: String) -> AppSettings {
        var settings: AppSettings
        if let data = storage.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = migrated(storage: storage)
        }
        // Direct writers may have changed a key since the blob was written.
        readLegacyOwned(into: &settings, storage: storage)
        settings.normalize()
        return settings
    }

    /// Builds settings from the legacy keys for a install that has no blob yet.
    private static func migrated(storage: any SettingsStorage) -> AppSettings {
        var migrated = AppSettings()
        if let raw = storage.string(forKey: AppSettingsKey.appearance.rawValue),
            let appearance = AppSettings.Appearance(rawValue: raw)
        {
            migrated.appearance = appearance
        }
        let density = storage.double(forKey: AppSettingsKey.rowDensity.rawValue)
        if density > 0 { migrated.rowDensity = density }
        migrated.highContrast = storage.bool(forKey: AppSettingsKey.highContrast.rawValue)
        migrated.hideEmptyGraphs = storage.bool(forKey: AppSettingsKey.hideEmptyGraphs.rawValue)
        migrated.showChannelRecommendations =
            storage.object(forKey: AppSettingsKey.graphChannel.rawValue) as? Bool ?? true
        migrated.showSecurityAudit =
            storage.object(forKey: AppSettingsKey.graphSecurity.rawValue) as? Bool ?? true
        migrated.showChannelOccupancy =
            storage.object(forKey: AppSettingsKey.graphOccupancy.rawValue) as? Bool ?? true
        migrated.toolbarSearch =
            storage.object(forKey: AppSettingsKey.toolbarSearch.rawValue) as? Bool ?? true
        migrated.toolbarExport =
            storage.object(forKey: AppSettingsKey.toolbarExport.rawValue) as? Bool ?? true
        migrated.scanOnLaunch =
            storage.object(forKey: AppSettingsKey.scanOnLaunch.rawValue) as? Bool ?? true
        let interval = storage.double(forKey: AppSettingsKey.refreshInterval.rawValue)
        if interval >= 0.5 { migrated.refreshInterval = interval }
        if let rawMetric = storage.string(forKey: AppSettingsKey.menuBarMetric.rawValue),
            let metric = AppSettings.MenuBarMeterSettings.Metric(rawValue: rawMetric)
        {
            migrated.menuBar.metric = metric
        }
        if let rawStyle = storage.string(forKey: AppSettingsKey.menuBarStyle.rawValue),
            let style = AppSettings.MenuBarMeterSettings.LabelStyle(rawValue: rawStyle)
        {
            migrated.menuBar.labelStyle = style
        }
        if let rawUnit = storage.string(forKey: AppSettingsKey.menuBarUnit.rawValue),
            let unit = AppSettings.MenuBarMeterSettings.Unit(rawValue: rawUnit)
        {
            migrated.menuBar.unit = unit
        }
        return migrated
    }

    // MARK: - Legacy-owned keys

    /// Reads the keys that older screens still own, so the model always carries
    /// their current value.
    private static func readLegacyOwned(into settings: inout AppSettings, storage: any SettingsStorage) {
        func bool(_ key: AppSettingsKey, _ fallback: Bool) -> Bool {
            storage.object(forKey: key.rawValue) as? Bool ?? fallback
        }
        func string(_ key: AppSettingsKey, _ fallback: String) -> String {
            storage.string(forKey: key.rawValue) ?? fallback
        }
        func int(_ key: AppSettingsKey, _ fallback: Int) -> Int {
            guard storage.object(forKey: key.rawValue) != nil else { return fallback }
            return storage.integer(forKey: key.rawValue)
        }
        func double(_ key: AppSettingsKey, _ fallback: Double) -> Double {
            guard storage.object(forKey: key.rawValue) != nil else { return fallback }
            return storage.double(forKey: key.rawValue)
        }

        settings.scan.band24 = bool(.filterBand24, settings.scan.band24)
        settings.scan.band5 = bool(.filterBand5, settings.scan.band5)
        settings.scan.band6 = bool(.filterBand6, settings.scan.band6)
        settings.scan.bandOther = bool(.filterOther, settings.scan.bandOther)
        settings.scan.wifi7 = bool(.filterWiFi7, settings.scan.wifi7)
        settings.scan.minSignal = double(.minSignal, settings.scan.minSignal)
        settings.scan.removeAfter = double(.removeAfter, settings.scan.removeAfter)
        settings.scan.highlightConnected = bool(.highlightConnected, settings.scan.highlightConnected)
        settings.scan.reduceInBackground = bool(
            .scanReduceInBackground, settings.scan.reduceInBackground)
        settings.scan.dwellMilliseconds = int(.scanDwellMilliseconds, settings.scan.dwellMilliseconds)
        settings.scan.groupMode =
            AppSettings.GroupMode(rawValue: string(.groupMode, settings.scan.groupMode.rawValue))
            ?? settings.scan.groupMode
        settings.scan.signalUnit =
            AppSettings.SignalUnit(rawValue: string(.signalUnit, settings.scan.signalUnit.rawValue))
            ?? settings.scan.signalUnit
        settings.scan.sortKey = string(.sortKey, settings.scan.sortKey)
        settings.scan.sortAscending = bool(.sortAscending, settings.scan.sortAscending)

        settings.alerts.weakSignal = bool(.alertsWeakSignal, settings.alerts.weakSignal)
        settings.alerts.openNetwork = bool(.alertsOpenNetwork, settings.alerts.openNetwork)
        settings.alerts.channelChange = bool(.alertsChannelChange, settings.alerts.channelChange)

        settings.monitor.recording = bool(.monitorRecording, settings.monitor.recording)
        settings.monitor.retention =
            AppSettings.MonitorRetention(
                rawValue: string(.monitorRetention, settings.monitor.retention.rawValue))
            ?? settings.monitor.retention

        settings.connectivity.enabled = bool(.connectivityEnabled, settings.connectivity.enabled)
        settings.connectivity.intervalSeconds = double(
            .connectivityInterval, settings.connectivity.intervalSeconds)
        settings.connectivity.primaryProbeURL = string(
            .connectivityPrimaryURL, settings.connectivity.primaryProbeURL)
        settings.connectivity.fallbackProbeURL = string(
            .connectivityFallbackURL, settings.connectivity.fallbackProbeURL)
        settings.connectivity.notifyOffline = bool(
            .connectivityNotifyOffline, settings.connectivity.notifyOffline)
        settings.connectivity.notifyCaptivePortal = bool(
            .connectivityNotifyCaptive, settings.connectivity.notifyCaptivePortal)
        settings.connectivity.notifyRestored = bool(
            .connectivityNotifyRestored, settings.connectivity.notifyRestored)

        settings.capture.autoOpenWireshark = bool(
            .captureAutoWireshark, settings.capture.autoOpenWireshark)

        settings.survey.heatmapDetail =
            AppSettings.SurveyHeatmapDetail(
                rawValue: string(.surveyHeatmapDetail, settings.survey.heatmapDetail.rawValue))
            ?? settings.survey.heatmapDetail

        settings.reports.enabled = bool(.reportsEnabled, settings.reports.enabled)
        settings.reports.minutes = int(.reportsMinutes, settings.reports.minutes)
        settings.reports.folder = string(.reportsFolder, settings.reports.folder)
        settings.reports.format =
            AppSettings.ReportFormat(
                rawValue: string(.reportsFormat, settings.reports.format.rawValue))
            ?? settings.reports.format

        settings.mcp.publishSnapshot = bool(.mcpPublishSnapshot, settings.mcp.publishSnapshot)
        settings.mcp.clientName = string(.mcpClientName, settings.mcp.clientName)
        settings.mcp.cliPath = string(.mcpCLIPath, settings.mcp.cliPath)

        settings.automation.speedTestCadence =
            AppSettings.SpeedTestCadence(
                rawValue: string(
                    .speedTestSchedule, settings.automation.speedTestCadence.rawValue))
            ?? settings.automation.speedTestCadence
        settings.automation.lanGuardEnabled = bool(
            .lanGuardEnabled, settings.automation.lanGuardEnabled)
        settings.automation.processTrafficEnabled = bool(
            .processTrafficEnabled, settings.automation.processTrafficEnabled)
        settings.automation.listenerWatch = bool(
            .listenerWatch, settings.automation.listenerWatch)
        settings.automation.serviceDescriptions = bool(
            .serviceDescriptions, settings.automation.serviceDescriptions)
        settings.automation.gatewayGuard = bool(
            .gatewayGuard, settings.automation.gatewayGuard)
        settings.automation.autoUpdateOUI = bool(
            .autoUpdateOUI, settings.automation.autoUpdateOUI)

        settings.display.historyChartMode =
            AppSettings.HistoryChartMode(
                rawValue: string(.historyChartMode, settings.display.historyChartMode.rawValue))
            ?? settings.display.historyChartMode
        settings.display.colorBlindSafe = bool(.colorBlindSafe, settings.display.colorBlindSafe)

        settings.networkInterface.preferred = string(
            .wifiInterface, settings.networkInterface.preferred)

        settings.layout.showInspector = bool(.showInspector, settings.layout.showInspector)
        settings.layout.bottomTab = int(.bottomTab, settings.layout.bottomTab)
        settings.layout.inspectorWidth = double(.inspectorWidth, settings.layout.inspectorWidth)
        settings.layout.bottomPanelHeight = double(
            .bottomPanelHeight, settings.layout.bottomPanelHeight)
        settings.layout.toolkitSelection = string(
            .toolkitSelection, settings.layout.toolkitSelection)
        settings.layout.toolkitSidebarWidth = double(
            .toolkitSidebarWidth, settings.layout.toolkitSidebarWidth)
        settings.layout.lanScannerTab = int(.lanScannerTab, settings.layout.lanScannerTab)
        settings.layout.settingsSection = string(.settingsSection, settings.layout.settingsSection)
        settings.layout.tabLayoutVersion = int(.tabLayoutVersion, settings.layout.tabLayoutVersion)
        settings.layout.hasCompletedFirstRun = bool(
            .hasCompletedFirstRun, settings.layout.hasCompletedFirstRun)
    }

    /// Writes the legacy-owned keys after an import or a reset.
    private static func writeLegacyOwned(_ settings: AppSettings, storage: any SettingsStorage) {
        storage.set(settings.scan.band24, forKey: AppSettingsKey.filterBand24.rawValue)
        storage.set(settings.scan.band5, forKey: AppSettingsKey.filterBand5.rawValue)
        storage.set(settings.scan.band6, forKey: AppSettingsKey.filterBand6.rawValue)
        storage.set(settings.scan.bandOther, forKey: AppSettingsKey.filterOther.rawValue)
        storage.set(settings.scan.wifi7, forKey: AppSettingsKey.filterWiFi7.rawValue)
        storage.set(settings.scan.minSignal, forKey: AppSettingsKey.minSignal.rawValue)
        storage.set(settings.scan.removeAfter, forKey: AppSettingsKey.removeAfter.rawValue)
        storage.set(
            settings.scan.highlightConnected, forKey: AppSettingsKey.highlightConnected.rawValue)
        storage.set(
            settings.scan.reduceInBackground, forKey: AppSettingsKey.scanReduceInBackground.rawValue)
        storage.set(
            settings.scan.dwellMilliseconds, forKey: AppSettingsKey.scanDwellMilliseconds.rawValue)
        storage.set(settings.scan.groupMode.rawValue, forKey: AppSettingsKey.groupMode.rawValue)
        storage.set(settings.scan.signalUnit.rawValue, forKey: AppSettingsKey.signalUnit.rawValue)
        storage.set(settings.scan.sortKey, forKey: AppSettingsKey.sortKey.rawValue)
        storage.set(settings.scan.sortAscending, forKey: AppSettingsKey.sortAscending.rawValue)

        storage.set(settings.alerts.weakSignal, forKey: AppSettingsKey.alertsWeakSignal.rawValue)
        storage.set(settings.alerts.openNetwork, forKey: AppSettingsKey.alertsOpenNetwork.rawValue)
        storage.set(
            settings.alerts.channelChange, forKey: AppSettingsKey.alertsChannelChange.rawValue)

        storage.set(settings.monitor.recording, forKey: AppSettingsKey.monitorRecording.rawValue)
        storage.set(
            settings.monitor.retention.rawValue, forKey: AppSettingsKey.monitorRetention.rawValue)

        storage.set(
            settings.connectivity.enabled, forKey: AppSettingsKey.connectivityEnabled.rawValue)
        storage.set(
            settings.connectivity.intervalSeconds, forKey: AppSettingsKey.connectivityInterval.rawValue)
        storage.set(
            settings.connectivity.primaryProbeURL,
            forKey: AppSettingsKey.connectivityPrimaryURL.rawValue)
        storage.set(
            settings.connectivity.fallbackProbeURL,
            forKey: AppSettingsKey.connectivityFallbackURL.rawValue)
        storage.set(
            settings.connectivity.notifyOffline,
            forKey: AppSettingsKey.connectivityNotifyOffline.rawValue)
        storage.set(
            settings.connectivity.notifyCaptivePortal,
            forKey: AppSettingsKey.connectivityNotifyCaptive.rawValue)
        storage.set(
            settings.connectivity.notifyRestored,
            forKey: AppSettingsKey.connectivityNotifyRestored.rawValue)

        storage.set(
            settings.capture.autoOpenWireshark, forKey: AppSettingsKey.captureAutoWireshark.rawValue)

        storage.set(
            settings.survey.heatmapDetail.rawValue,
            forKey: AppSettingsKey.surveyHeatmapDetail.rawValue)

        storage.set(settings.reports.enabled, forKey: AppSettingsKey.reportsEnabled.rawValue)
        storage.set(settings.reports.minutes, forKey: AppSettingsKey.reportsMinutes.rawValue)
        storage.set(settings.reports.folder, forKey: AppSettingsKey.reportsFolder.rawValue)
        storage.set(settings.reports.format.rawValue, forKey: AppSettingsKey.reportsFormat.rawValue)

        storage.set(
            settings.mcp.publishSnapshot, forKey: AppSettingsKey.mcpPublishSnapshot.rawValue)
        storage.set(settings.mcp.clientName, forKey: AppSettingsKey.mcpClientName.rawValue)
        storage.set(settings.mcp.cliPath, forKey: AppSettingsKey.mcpCLIPath.rawValue)

        storage.set(
            settings.automation.speedTestCadence.rawValue,
            forKey: AppSettingsKey.speedTestSchedule.rawValue)
        storage.set(
            settings.automation.lanGuardEnabled, forKey: AppSettingsKey.lanGuardEnabled.rawValue)
        storage.set(
            settings.automation.processTrafficEnabled,
            forKey: AppSettingsKey.processTrafficEnabled.rawValue)
        storage.set(settings.automation.listenerWatch, forKey: AppSettingsKey.listenerWatch.rawValue)
        storage.set(
            settings.automation.serviceDescriptions,
            forKey: AppSettingsKey.serviceDescriptions.rawValue)
        storage.set(settings.automation.gatewayGuard, forKey: AppSettingsKey.gatewayGuard.rawValue)
        storage.set(settings.automation.autoUpdateOUI, forKey: AppSettingsKey.autoUpdateOUI.rawValue)

        storage.set(
            settings.display.historyChartMode.rawValue,
            forKey: AppSettingsKey.historyChartMode.rawValue)
        storage.set(settings.display.colorBlindSafe, forKey: AppSettingsKey.colorBlindSafe.rawValue)

        storage.set(
            settings.networkInterface.preferred, forKey: AppSettingsKey.wifiInterface.rawValue)

        storage.set(settings.layout.showInspector, forKey: AppSettingsKey.showInspector.rawValue)
        storage.set(settings.layout.bottomTab, forKey: AppSettingsKey.bottomTab.rawValue)
        storage.set(settings.layout.inspectorWidth, forKey: AppSettingsKey.inspectorWidth.rawValue)
        storage.set(
            settings.layout.bottomPanelHeight, forKey: AppSettingsKey.bottomPanelHeight.rawValue)
        storage.set(
            settings.layout.toolkitSelection, forKey: AppSettingsKey.toolkitSelection.rawValue)
        storage.set(
            settings.layout.toolkitSidebarWidth, forKey: AppSettingsKey.toolkitSidebarWidth.rawValue)
        storage.set(settings.layout.lanScannerTab, forKey: AppSettingsKey.lanScannerTab.rawValue)
        storage.set(
            settings.layout.settingsSection, forKey: AppSettingsKey.settingsSection.rawValue)
        storage.set(
            settings.layout.tabLayoutVersion, forKey: AppSettingsKey.tabLayoutVersion.rawValue)
        storage.set(
            settings.layout.hasCompletedFirstRun, forKey: AppSettingsKey.hasCompletedFirstRun.rawValue)
    }

    // MARK: - Canonical mirrors

    private static func writeLegacy(_ settings: AppSettings, storage: any SettingsStorage) {
        storage.set(settings.appearance.rawValue, forKey: AppSettingsKey.appearance.rawValue)
        storage.set(settings.rowDensity, forKey: AppSettingsKey.rowDensity.rawValue)
        storage.set(settings.highContrast, forKey: AppSettingsKey.highContrast.rawValue)
        storage.set(settings.hideEmptyGraphs, forKey: AppSettingsKey.hideEmptyGraphs.rawValue)
        storage.set(
            settings.showChannelRecommendations, forKey: AppSettingsKey.graphChannel.rawValue)
        storage.set(settings.showSecurityAudit, forKey: AppSettingsKey.graphSecurity.rawValue)
        storage.set(settings.showChannelOccupancy, forKey: AppSettingsKey.graphOccupancy.rawValue)
        storage.set(settings.toolbarSearch, forKey: AppSettingsKey.toolbarSearch.rawValue)
        storage.set(settings.toolbarExport, forKey: AppSettingsKey.toolbarExport.rawValue)
        storage.set(settings.scanOnLaunch, forKey: AppSettingsKey.scanOnLaunch.rawValue)
        storage.set(settings.refreshInterval, forKey: AppSettingsKey.refreshInterval.rawValue)
        storage.set(settings.menuBar.metric.rawValue, forKey: AppSettingsKey.menuBarMetric.rawValue)
        storage.set(settings.menuBar.labelStyle.rawValue, forKey: AppSettingsKey.menuBarStyle.rawValue)
        storage.set(settings.menuBar.unit.rawValue, forKey: AppSettingsKey.menuBarUnit.rawValue)
    }
}
