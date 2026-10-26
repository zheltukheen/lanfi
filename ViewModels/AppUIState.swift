import Foundation

final class AppUIState: ObservableObject {
    @Published var showSidebar: Bool = false { didSet { store() } }
    @Published var showInspector: Bool = true { didSet { store() } }
    @Published var selectedBottomTab: Int = 0 { didSet { store() } }
    @Published var customIntervalText: String = ""
    @Published var showingCustomIntervalAlert: Bool = false

    private static let tabLayoutVersion = 2

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "Wifa.showSidebar") != nil {
            showSidebar = defaults.bool(forKey: "Wifa.showSidebar")
        }
        if defaults.object(forKey: "Wifa.showInspector") != nil {
            showInspector = defaults.bool(forKey: "Wifa.showInspector")
        }

        // Tab indices changed in 1.4: Insights is now the first and default tab.
        // Migrate old layouts once instead of showing the wrong panel.
        let layoutVersion = defaults.integer(forKey: "Wifa.tabLayoutVersion")
        if layoutVersion < 2 {
            // 1.5 order: Insights, Spectrum, History, Raw Data, Protocols, Diagnostics.
            // 1.6 order: Insights, Spectrum, History, Protocols, Raw Data, Diagnostics.
            let old =
                defaults.object(forKey: "Wifa.bottomTab") != nil
                ? defaults.integer(forKey: "Wifa.bottomTab")
                : 0
            let mapped = [0: 0, 1: 1, 2: 2, 3: 4, 4: 3, 5: 5][old] ?? 0
            selectedBottomTab = mapped
            defaults.set(Self.tabLayoutVersion, forKey: "Wifa.tabLayoutVersion")
            defaults.set(mapped, forKey: "Wifa.bottomTab")
        } else if defaults.object(forKey: "Wifa.bottomTab") != nil {
            selectedBottomTab = defaults.integer(forKey: "Wifa.bottomTab")
        }
    }

    private func store() {
        let defaults = UserDefaults.standard
        defaults.set(showSidebar, forKey: "Wifa.showSidebar")
        defaults.set(showInspector, forKey: "Wifa.showInspector")
        defaults.set(selectedBottomTab, forKey: "Wifa.bottomTab")
    }
}
