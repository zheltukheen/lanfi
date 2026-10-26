import SwiftUI

private struct LanFiHighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var lanFiHighContrast: Bool {
        get { self[LanFiHighContrastKey.self] }
        set { self[LanFiHighContrastKey.self] = newValue }
    }
}
