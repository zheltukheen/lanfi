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

/// Table geometry that every column, header and row shares.
enum TableMetrics {
    /// Space between a cell's text and its column separators.
    static let cellInset = Theme.Spacing.small
    /// A column can never be dragged narrower than this; below it the sort
    /// chevron and two characters no longer fit.
    static var minColumnWidth: CGFloat { TableColumnLayout.minColumnWidth }
    /// The grab area on a column's trailing edge.
    static let resizeHandleWidth: CGFloat = 7
    /// Header text height, so every table's header is the same band.
    static let headerHeight: CGFloat = 24
    /// How far a drag must move before it counts as a resize, so a sort click
    /// on the header never resizes by accident.
    static let resizeThreshold: CGFloat = 1
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
