import LanFiCore
import Foundation

/// Colour-blind-safe replacements for the semantic roles that carry meaning
/// (quality, status, band). Standard mode keeps the system colours; the safe
/// mode uses five Okabe–Ito hues, which stay distinguishable for the common
/// red–green and blue–yellow deficiencies.
///
/// The flag is cached rather than read from `UserDefaults` on every call:
/// `AppPalette` resolves a colour while drawing each table cell and chart
/// segment, and a defaults lookup there costs a plist round trip per cell.
/// The settings toggle writes through `setEnabled(_:)` before the window
/// redraws, so the cached value is never stale on screen.
enum AccessibilityPalette {
    static let colorBlindSafeKey = AppSettingsKey.colorBlindSafe.rawValue

    enum Role: CaseIterable {
        case success
        case warning
        case danger
        case excellent
        case good
        case fair
        case poor
        case band24
        case band5
        case band6
    }

    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// Ten roles resolve to five hues; only the meaning picks the hue, so a
    /// new role cannot invent a sixth colour by accident.
    static func safeColor(for role: Role) -> RGB {
        switch role {
        case .success, .excellent, .band5: return blue
        case .good: return sky
        case .warning, .fair, .band24: return amber
        case .danger, .poor: return vermillion
        case .band6: return magenta
        }
    }

    private static let blue = RGB(red: 0.000, green: 0.447, blue: 0.698)
    private static let sky = RGB(red: 0.337, green: 0.706, blue: 0.914)
    private static let amber = RGB(red: 0.902, green: 0.624, blue: 0.000)
    private static let vermillion = RGB(red: 0.835, green: 0.369, blue: 0.000)
    private static let magenta = RGB(red: 0.800, green: 0.474, blue: 0.655)

    /// Seeded from the standard domain, so a launch argument
    /// (`-LanFi.colorBlindSafe YES`) is honoured before the first window draws.
    private(set) static var isEnabled = UserDefaults.standard.bool(forKey: colorBlindSafeKey)

    static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    static func reload(from defaults: UserDefaults = .standard) {
        isEnabled = defaults.bool(forKey: colorBlindSafeKey)
    }
}
