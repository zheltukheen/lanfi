import Foundation

/// Typed, versioned application preferences.
///
/// This is the first tranche of the settings migration: appearance, table
/// display, toolbar visibility, launch/scan cadence. The store writes the
/// legacy `LanFi.*` keys as well so existing `@AppStorage` readers keep working
/// while the rest of the app is migrated incrementally.
public struct AppSettings: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark
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

    /// Non-optional accessor for the menu-bar meter preferences.
    public var menuBar: MenuBarMeterSettings {
        get { menuBarMeter ?? MenuBarMeterSettings() }
        set { menuBarMeter = newValue }
    }

    public init() {}

    /// Keeps values in the ranges the UI actually supports.
    public mutating func normalize() {
        if !(0.5...60).contains(refreshInterval) {
            refreshInterval = 3
        }
        if ![24, 30, 38].contains(rowDensity) {
            rowDensity = 30
        }
    }
}
