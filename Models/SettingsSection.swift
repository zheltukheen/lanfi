import Foundation

/// One page of the Settings window. Declared in Models so the command palette
/// and its tests can name a destination the way the sidebar does, instead of
/// keeping a second list of tab titles.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case alerts
    case wifi
    case vendors
    case colors
    case columns
    case diagnostics
    case hardware
    case automation
    case controllers
    case mcp
    case privacy
    case toolkit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .alerts: return String(localized: "Alerts")
        case .wifi: return String(localized: "Wi-Fi")
        case .vendors: return String(localized: "Vendors")
        case .colors: return String(localized: "Colors")
        case .columns: return String(localized: "Columns")
        case .diagnostics: return String(localized: "Diagnostics")
        case .hardware: return String(localized: "Hardware")
        case .automation: return String(localized: "Automation")
        case .controllers: return String(localized: "Controllers")
        case .mcp: return String(localized: "MCP")
        case .privacy: return String(localized: "Privacy")
        case .toolkit: return String(localized: "Toolkit")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .alerts: return "bell"
        case .wifi: return "wifi"
        case .vendors: return "building.2"
        case .colors: return "paintpalette"
        case .columns: return "tablecells"
        case .diagnostics: return "stethoscope"
        case .hardware: return "cable.connector"
        case .automation: return "clock.arrow.circlepath"
        case .controllers: return "server.rack"
        case .mcp: return "sparkles"
        case .privacy: return "hand.raised"
        case .toolkit: return "wrench.and.screwdriver"
        }
    }
}
