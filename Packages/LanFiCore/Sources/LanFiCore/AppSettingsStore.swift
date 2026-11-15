import Foundation

public enum AppSettingsError: Error, Equatable {
    case invalidData
}

/// Loads, migrates, exports and persists `AppSettings`.
///
/// The JSON blob is canonical. The legacy keys are mirrored so the remaining
/// `@AppStorage` readers continue to update until they are migrated too.
public final class AppSettingsStore {
    public static let shared = AppSettingsStore()

    public private(set) var settings: AppSettings

    private let defaults: UserDefaults
    private let storageKey = "LanFi.settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.load(defaults: defaults, storageKey: storageKey)
    }

    public func save(_ newSettings: AppSettings) {
        var normalized = newSettings
        normalized.normalize()
        settings = normalized

        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: storageKey)
        }
        writeLegacy(normalized)
    }

    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    public func importData(_ data: Data) throws {
        guard let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            throw AppSettingsError.invalidData
        }
        save(decoded)
    }

    public func reset() {
        defaults.removeObject(forKey: storageKey)
        settings = AppSettings()
        writeLegacy(settings)
    }

    private static func load(defaults: UserDefaults, storageKey: String) -> AppSettings {
        if let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            var normalized = decoded
            normalized.normalize()
            return normalized
        }

        var migrated = AppSettings()
        if let raw = defaults.string(forKey: "LanFi.appearance"),
            let appearance = AppSettings.Appearance(rawValue: raw)
        {
            migrated.appearance = appearance
        }
        let density = defaults.double(forKey: "LanFi.rowDensity")
        if density > 0 { migrated.rowDensity = density }
        migrated.highContrast = defaults.bool(forKey: "LanFi.highContrast")
        migrated.hideEmptyGraphs = defaults.bool(forKey: "LanFi.hideEmptyGraphs")
        migrated.showChannelRecommendations =
            defaults.object(forKey: "LanFi.graph.channel") as? Bool ?? true
        migrated.showSecurityAudit =
            defaults.object(forKey: "LanFi.graph.security") as? Bool ?? true
        migrated.showChannelOccupancy =
            defaults.object(forKey: "LanFi.graph.occupancy") as? Bool ?? true
        migrated.toolbarSearch =
            defaults.object(forKey: "LanFi.toolbar.search") as? Bool ?? true
        migrated.toolbarExport =
            defaults.object(forKey: "LanFi.toolbar.export") as? Bool ?? true
        migrated.scanOnLaunch =
            defaults.object(forKey: "LanFi.scanOnLaunch") as? Bool ?? true
        let interval = defaults.double(forKey: "RefreshIntervalSeconds")
        if interval >= 0.5 { migrated.refreshInterval = interval }
        migrated.normalize()
        return migrated
    }

    private func writeLegacy(_ settings: AppSettings) {
        defaults.set(settings.appearance.rawValue, forKey: "LanFi.appearance")
        defaults.set(settings.rowDensity, forKey: "LanFi.rowDensity")
        defaults.set(settings.highContrast, forKey: "LanFi.highContrast")
        defaults.set(settings.hideEmptyGraphs, forKey: "LanFi.hideEmptyGraphs")
        defaults.set(settings.showChannelRecommendations, forKey: "LanFi.graph.channel")
        defaults.set(settings.showSecurityAudit, forKey: "LanFi.graph.security")
        defaults.set(settings.showChannelOccupancy, forKey: "LanFi.graph.occupancy")
        defaults.set(settings.toolbarSearch, forKey: "LanFi.toolbar.search")
        defaults.set(settings.toolbarExport, forKey: "LanFi.toolbar.export")
        defaults.set(settings.scanOnLaunch, forKey: "LanFi.scanOnLaunch")
        defaults.set(settings.refreshInterval, forKey: "RefreshIntervalSeconds")
    }
}
