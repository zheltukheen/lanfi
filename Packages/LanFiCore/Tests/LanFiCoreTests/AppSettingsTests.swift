import XCTest
@testable import LanFiCore

final class AppSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LanFiCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaults() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.appearance, .system)
        XCTAssertEqual(store.settings.rowDensity, 30)
        XCTAssertTrue(store.settings.toolbarSearch)
        XCTAssertTrue(store.settings.scanOnLaunch)
        XCTAssertEqual(store.settings.refreshInterval, 3)
    }

    func testMigratesLegacyKeys() {
        defaults.set("dark", forKey: "LanFi.appearance")
        defaults.set(38.0, forKey: "LanFi.rowDensity")
        defaults.set(true, forKey: "LanFi.highContrast")
        defaults.set(false, forKey: "LanFi.graph.channel")
        defaults.set(10.0, forKey: "RefreshIntervalSeconds")

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.appearance, .dark)
        XCTAssertEqual(store.settings.rowDensity, 38)
        XCTAssertTrue(store.settings.highContrast)
        XCTAssertFalse(store.settings.showChannelRecommendations)
        XCTAssertEqual(store.settings.refreshInterval, 10)
    }

    func testSaveWritesLegacyKeysAndReloads() {
        let store = AppSettingsStore(defaults: defaults)
        var settings = store.settings
        settings.appearance = .light
        settings.highContrast = true
        settings.refreshInterval = 5
        store.save(settings)

        XCTAssertEqual(defaults.string(forKey: "LanFi.appearance"), "light")
        XCTAssertTrue(defaults.bool(forKey: "LanFi.highContrast"))
        XCTAssertEqual(defaults.double(forKey: "RefreshIntervalSeconds"), 5)

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings, settings)
    }

    func testExportImportRoundTrip() throws {
        let store = AppSettingsStore(defaults: defaults)
        var settings = store.settings
        settings.appearance = .dark
        settings.rowDensity = 24
        store.save(settings)

        let data = try store.exportData()
        let imported = AppSettingsStore(defaults: defaults)
        try imported.importData(data)
        XCTAssertEqual(imported.settings, settings)
    }

    func testInvalidImportIsRejected() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertThrowsError(try store.importData(Data("not json".utf8)))
    }

    func testMenuBarMeterDefaultsAndLegacyMirror() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.menuBar.metric, .throughput)
        XCTAssertEqual(store.settings.menuBar.labelStyle, .iconAndGraph)
        XCTAssertEqual(store.settings.menuBar.unit, .bits)

        var settings = store.settings
        settings.menuBar.metric = .latency
        settings.menuBar.labelStyle = .iconAndNumber
        settings.menuBar.unit = .bytes
        store.save(settings)

        XCTAssertEqual(defaults.string(forKey: "LanFi.menuBar.metric"), "latency")
        XCTAssertEqual(defaults.string(forKey: "LanFi.menuBar.style"), "iconAndNumber")
        XCTAssertEqual(defaults.string(forKey: "LanFi.menuBar.unit"), "bytes")

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.menuBar, settings.menuBar)
    }

    func testSettingsWithoutMenuBarKeyStillDecode() throws {
        // Settings written before the menu-bar meter existed must keep their values.
        var settings = AppSettings()
        settings.appearance = .dark
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
        if var dictionary = object as? [String: Any] {
            dictionary.removeValue(forKey: "menuBarMeter")
            object = dictionary
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.menuBar, AppSettings.MenuBarMeterSettings())
    }

    func testNormalizeClampsUnsupportedValues() {
        var settings = AppSettings()
        settings.rowDensity = 99
        settings.refreshInterval = 0
        settings.normalize()

        XCTAssertEqual(settings.rowDensity, 30)
        XCTAssertEqual(settings.refreshInterval, 3)
    }
}
