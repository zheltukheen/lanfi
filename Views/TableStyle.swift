import LanFiCore
import SwiftUI

private struct TableDensityEnvironmentKey: EnvironmentKey {
    static let defaultValue = TableDensity.regular
}

extension EnvironmentValues {
    /// Row density shared by every table and list in the app.
    var appTableDensity: TableDensity {
        get { self[TableDensityEnvironmentKey.self] }
        set { self[TableDensityEnvironmentKey.self] = newValue }
    }
}

extension TableDensity {
    var controlSize: ControlSize {
        switch self {
        case .compact: return .small
        case .regular: return .regular
        case .comfortable: return .large
        }
    }
}

/// Applies the Settings row density live: SwiftUI reads the same
/// `LanFi.rowDensity` key, so switching Compact/Standard/Roomy updates every
/// list, table and control size without relaunching.
private struct AppTableDensityModifier: ViewModifier {
    @AppStorage(AppSettingsKey.rowDensity.rawValue) private var rowHeight = TableDensity.regular.rowHeight

    func body(content: Content) -> some View {
        let density = TableDensity.resolve(rowHeight: rowHeight)
        content
            .environment(\.appTableDensity, density)
            .environment(\.defaultMinListRowHeight, density.rowHeight)
            .environment(\.controlSize, density.controlSize)
    }
}

extension View {
    func appTableDensity() -> some View {
        modifier(AppTableDensityModifier())
    }
}
