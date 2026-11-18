import XCTest
@testable import LanFiCore

/// Covers the second settings tranche: every remaining `LanFi.*` key is typed in
/// `AppSettings`, mirrored to its legacy key, and never rolled back by a save.
final class AppSettingsMigrationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LanFiCoreTests.migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testKeyCatalogIsUniqueAndComplete() {
        let keys = AppSettingsKey.allPersistedKeys
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(keys.count, AppSettingsKey.allCases.count)
        XCTAssertEqual(AppSettingsKey.settingsBlob.rawValue, "LanFi.settings.v1")
        XCTAssertEqual(AppSettingsKey.refreshInterval.rawValue, "RefreshIntervalSeconds")
        XCTAssertEqual(AppSettingsKey.menuBarMetric.rawValue, "LanFi.menuBar.metric")
    }

    func testMigratesMonitorCaptureSurveyReportsAndMCPKeys() {
        defaults.set(false, forKey: "LanFi.monitor.recording")
        defaults.set("week", forKey: "LanFi.monitor.retention")
        defaults.set(true, forKey: "LanFi.capture.autoWireshark")
        defaults.set("high", forKey: "LanFi.survey.heatmapDetail")
        defaults.set(true, forKey: "LanFi.reports.enabled")
        defaults.set(30, forKey: "LanFi.reports.minutes")
        defaults.set("/tmp/reports", forKey: "LanFi.reports.folder")
        defaults.set("PDF", forKey: "LanFi.reports.format")
        defaults.set(false, forKey: "LanFi.mcp.publishSnapshot")
        defaults.set("workstation", forKey: "LanFi.mcp.clientName")
        defaults.set("/opt/bin/lanfi-cli", forKey: "LanFi.mcp.cliPath")

        let settings = AppSettingsStore(defaults: defaults).settings
        XCTAssertFalse(settings.monitor.recording)
        XCTAssertEqual(settings.monitor.retention, .week)
        XCTAssertTrue(settings.capture.autoOpenWireshark)
        XCTAssertEqual(settings.survey.heatmapDetail, .high)
        XCTAssertTrue(settings.reports.enabled)
        XCTAssertEqual(settings.reports.minutes, 30)
        XCTAssertEqual(settings.reports.folder, "/tmp/reports")
        XCTAssertEqual(settings.reports.format, .pdf)
        XCTAssertFalse(settings.mcp.publishSnapshot)
        XCTAssertEqual(settings.mcp.clientName, "workstation")
        XCTAssertEqual(settings.mcp.cliPath, "/opt/bin/lanfi-cli")
    }

    func testMigratesScanAlertsAutomationAndLayoutKeys() {
        defaults.set(false, forKey: "LanFi.filterBand24")
        defaults.set(-70.0, forKey: "LanFi.minSignal")
        defaults.set(300.0, forKey: "LanFi.removeAfter")
        defaults.set("ssid", forKey: "LanFi.groupMode")
        defaults.set("%", forKey: "LanFi.signalUnit")
        defaults.set(250, forKey: "LanFi.scan.dwellMilliseconds")
        defaults.set(true, forKey: "LanFi.scan.reduceInBackground")
        defaults.set(false, forKey: "LanFi.alerts.weakSignal")
        defaults.set("hourly", forKey: "LanFi.speedTestSchedule")
        defaults.set(true, forKey: "LanFi.lanGuardEnabled")
        defaults.set(true, forKey: "LanFi.processTraffic.enabled")
        defaults.set(false, forKey: "LanFi.autoUpdateOUI")
        defaults.set(true, forKey: "LanFi.colorBlindSafe")
        defaults.set("both", forKey: "LanFi.historyChart.mode")
        defaults.set("en1", forKey: "LanFi.wifiInterface")
        defaults.set(false, forKey: "LanFi.showInspector")
        defaults.set(4, forKey: "LanFi.bottomTab")
        defaults.set(340.0, forKey: "LanFi.inspectorWidth")
        defaults.set("lanScanner", forKey: "LanFi.toolkit.selection")

        let settings = AppSettingsStore(defaults: defaults).settings
        XCTAssertFalse(settings.scan.band24)
        XCTAssertEqual(settings.scan.minSignal, -70)
        XCTAssertEqual(settings.scan.removeAfter, 300)
        XCTAssertEqual(settings.scan.groupMode, .ssid)
        XCTAssertEqual(settings.scan.signalUnit, .percent)
        XCTAssertEqual(settings.scan.dwellMilliseconds, 250)
        XCTAssertTrue(settings.scan.reduceInBackground)
        XCTAssertFalse(settings.alerts.weakSignal)
        XCTAssertEqual(settings.automation.speedTestCadence, .hourly)
        XCTAssertTrue(settings.automation.lanGuardEnabled)
        XCTAssertTrue(settings.automation.processTrafficEnabled)
        XCTAssertFalse(settings.automation.autoUpdateOUI)
        XCTAssertTrue(settings.display.colorBlindSafe)
        XCTAssertEqual(settings.display.historyChartMode, .both)
        XCTAssertEqual(settings.networkInterface.preferred, "en1")
        XCTAssertFalse(settings.layout.showInspector)
        XCTAssertEqual(settings.layout.bottomTab, 4)
        XCTAssertEqual(settings.layout.inspectorWidth, 340)
        XCTAssertEqual(settings.layout.toolkitSelection, "lanScanner")
    }

    func testSaveKeepsDirectlyWrittenLegacyValues() {
        let store = AppSettingsStore(defaults: defaults)
        // Another screen writes its key directly, then General Settings saves.
        defaults.set("both", forKey: "LanFi.historyChart.mode")
        defaults.set("/tmp/out", forKey: "LanFi.reports.folder")
        defaults.set("en2", forKey: "LanFi.wifiInterface")

        var settings = store.settings
        settings.appearance = .dark
        store.save(settings)

        XCTAssertEqual(defaults.string(forKey: "LanFi.historyChart.mode"), "both")
        XCTAssertEqual(defaults.string(forKey: "LanFi.reports.folder"), "/tmp/out")
        XCTAssertEqual(defaults.string(forKey: "LanFi.wifiInterface"), "en2")
        XCTAssertEqual(store.settings.display.historyChartMode, .both)
        XCTAssertEqual(defaults.double(forKey: "LanFi.inspectorWidth"), 300)
    }

    func testImportIsAuthoritativeForLegacyOwnedKeys() throws {
        let store = AppSettingsStore(defaults: defaults)
        var imported = AppSettings()
        imported.reports.enabled = true
        imported.reports.folder = "/Volumes/reports"
        imported.monitor.retention = .month
        imported.appearance = .light
        let data = try JSONEncoder().encode(imported)

        try store.importData(data)

        XCTAssertEqual(defaults.string(forKey: "LanFi.reports.folder"), "/Volumes/reports")
        XCTAssertTrue(defaults.bool(forKey: "LanFi.reports.enabled"))
        XCTAssertEqual(defaults.string(forKey: "LanFi.monitor.retention"), "month")
        XCTAssertEqual(defaults.string(forKey: "LanFi.appearance"), "light")
        XCTAssertEqual(store.settings.monitor.retention, .month)
    }

    func testExportUsesInjectedClockAndFileStore() throws {
        let clock = FixedClock(Date(timeIntervalSince1970: 1_800_000_000))
        let files = RecordingFileStore()
        let store = AppSettingsStore(
            storage: UserDefaultsSettingsStorage(defaults: defaults),
            clock: clock,
            notifications: SilentNotificationPoster(),
            files: files)

        let url = URL(fileURLWithPath: "/tmp/lanfi-settings-test.json")
        try store.export(to: url)

        let data = try XCTUnwrap(files.data)
        let decoded = try JSONDecoder.iso8601.decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.lastModified, clock.now)
        XCTAssertEqual(files.writtenURL, url)
    }

    func testSavePostsChangeNotification() {
        let notifications = RecordingNotificationPoster()
        let store = AppSettingsStore(
            storage: UserDefaultsSettingsStorage(defaults: defaults),
            notifications: notifications)
        store.save(AppSettings())
        XCTAssertEqual(notifications.names, [.lanFiSettingsDidChange])
    }

    func testInMemoryStorageRoundTrip() {
        let storage = InMemorySettingsStorage()
        let store = AppSettingsStore(
            storage: storage, notifications: SilentNotificationPoster())
        var settings = store.settings
        settings.mcp.clientName = "agent"
        settings.scan.wifi7 = false
        store.save(settings)

        let reloaded = AppSettingsStore(
            storage: storage, notifications: SilentNotificationPoster())
        XCTAssertEqual(reloaded.settings.mcp.clientName, "agent")
        XCTAssertFalse(reloaded.settings.scan.wifi7)
        XCTAssertEqual(storage.string(forKey: "LanFi.mcp.clientName"), "agent")
    }

    func testOldBlobWithoutNewSectionsStillLoads() throws {
        let old = """
            {"appearance":"dark","rowDensity":38,"refreshInterval":5}
            """
        defaults.set(Data(old.utf8), forKey: "LanFi.settings.v1")
        let settings = AppSettingsStore(defaults: defaults).settings

        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(settings.rowDensity, 38)
        XCTAssertEqual(settings.refreshInterval, 5)
        XCTAssertEqual(settings.reports.format, .csv)
        XCTAssertEqual(settings.layout.bottomTab, 9)
        XCTAssertEqual(settings.monitor.retention, .day)
    }
}

// MARK: - Test doubles

extension JSONDecoder {
    fileprivate static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private final class RecordingFileStore: FileStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var url: URL?

    var data: Data? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    var writtenURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return url
    }

    func read(from url: URL) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        return stored ?? Data()
    }

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        stored = data
        self.url = url
        lock.unlock()
    }
}

private final class RecordingNotificationPoster: NotificationPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Notification.Name] = []

    var names: [Notification.Name] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func post(_ name: Notification.Name, userInfo: [String: String]?) {
        lock.lock()
        recorded.append(name)
        lock.unlock()
    }
}

private final class InMemorySettingsStorage: SettingsStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key] as? Data
    }

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key] as? String
    }

    func double(forKey key: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return (values[key] as? Double) ?? 0
    }

    func integer(forKey key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return (values[key] as? Int) ?? 0
    }

    func bool(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (values[key] as? Bool) ?? false
    }

    func object(forKey key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: Any?, forKey key: String) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    func removeObject(forKey key: String) {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
    }
}
