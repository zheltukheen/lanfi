import LanFiCore
import Foundation

final class AppUIState: ObservableObject {
    @Published var showInspector: Bool = true { didSet { store() } }
    /// Fresh installs open on the all-band RF overview; existing layouts keep
    /// whatever bottom tab they stored.
    @Published var selectedBottomTab: Int = 9 { didSet { store() } }
    @Published var customIntervalText: String = ""
    @Published var showingCustomIntervalAlert: Bool = false

    private static let tabLayoutVersion = 5

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppSettingsKey.showInspector.rawValue) != nil {
            showInspector = defaults.bool(forKey: AppSettingsKey.showInspector.rawValue)
        }

        // Tab indices changed in 1.4: Insights is now the first and default tab.
        // Migrate old layouts once instead of showing the wrong panel.
        let layoutVersion = defaults.integer(forKey: AppSettingsKey.tabLayoutVersion.rawValue)
        if layoutVersion < 4 {
            // 2.3: Overview, Spectrum, History, Profile, Interfaces, Raw, Diagnostics
            // 2.4: Overview, Profile, Interfaces, Raw, Spectrum, History, Diagnostics
            // A fresh install has no stored tab and keeps the all-bands default.
            if defaults.object(forKey: AppSettingsKey.bottomTab.rawValue) != nil {
                let old = defaults.integer(forKey: AppSettingsKey.bottomTab.rawValue)
                let mapped = [0: 0, 1: 4, 2: 5, 3: 1, 4: 2, 5: 3, 6: 6][old] ?? 0
                selectedBottomTab = mapped
                defaults.set(mapped, forKey: AppSettingsKey.bottomTab.rawValue)
            }
            defaults.set(Self.tabLayoutVersion, forKey: AppSettingsKey.tabLayoutVersion.rawValue)
        } else if defaults.object(forKey: AppSettingsKey.bottomTab.rawValue) != nil {
            selectedBottomTab = defaults.integer(forKey: AppSettingsKey.bottomTab.rawValue)
        }

        // 5.0: Interfaces and Diagnostics moved into the Network Toolkit.
        if layoutVersion < 5 {
            if selectedBottomTab == 2 || selectedBottomTab == 6 {
                selectedBottomTab = 0
            }
            defaults.set(Self.tabLayoutVersion, forKey: AppSettingsKey.tabLayoutVersion.rawValue)
        }
    }

    private func store() {
        let defaults = UserDefaults.standard
        defaults.set(showInspector, forKey: AppSettingsKey.showInspector.rawValue)
        defaults.set(selectedBottomTab, forKey: AppSettingsKey.bottomTab.rawValue)
    }
}
