import Foundation

final class AppUIState: ObservableObject {
    @Published var showSidebar: Bool = false { didSet { store() } }
    @Published var showInspector: Bool = true { didSet { store() } }
    @Published var selectedBottomTab: Int = 0 { didSet { store() } }
    @Published var customIntervalText: String = ""
    @Published var showingCustomIntervalAlert: Bool = false

    private static let tabLayoutVersion = 4

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "LanFi.showSidebar") != nil {
            showSidebar = defaults.bool(forKey: "LanFi.showSidebar")
        }
        if defaults.object(forKey: "LanFi.showInspector") != nil {
            showInspector = defaults.bool(forKey: "LanFi.showInspector")
        }

        // Tab indices changed in 1.4: Insights is now the first and default tab.
        // Migrate old layouts once instead of showing the wrong panel.
        let layoutVersion = defaults.integer(forKey: "LanFi.tabLayoutVersion")
        if layoutVersion < 4 {
            // 2.3: Overview, Spectrum, History, Profile, Interfaces, Raw, Diagnostics
            // 2.4: Overview, Profile, Interfaces, Raw, Spectrum, History, Diagnostics
            let old =
                defaults.object(forKey: "LanFi.bottomTab") != nil
                ? defaults.integer(forKey: "LanFi.bottomTab")
                : 0
            let mapped = [0: 0, 1: 4, 2: 5, 3: 1, 4: 2, 5: 3, 6: 6][old] ?? 0
            selectedBottomTab = mapped
            defaults.set(Self.tabLayoutVersion, forKey: "LanFi.tabLayoutVersion")
            defaults.set(mapped, forKey: "LanFi.bottomTab")
        } else if defaults.object(forKey: "LanFi.bottomTab") != nil {
            selectedBottomTab = defaults.integer(forKey: "LanFi.bottomTab")
        }
    }

    private func store() {
        let defaults = UserDefaults.standard
        defaults.set(showSidebar, forKey: "LanFi.showSidebar")
        defaults.set(showInspector, forKey: "LanFi.showInspector")
        defaults.set(selectedBottomTab, forKey: "LanFi.bottomTab")
    }
}
