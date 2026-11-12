import SwiftUI

/// The Wi-Fi workspace of the toolkit. It is the full analyzer — scan table,
/// filters, inspector and the bottom panels — embedded in the toolkit window,
/// which is now the app's main window.
struct WiFiAnalyzerToolView: View {
    @EnvironmentObject private var analyzer: AnalyzerViewModel
    @EnvironmentObject private var uiState: AppUIState

    var body: some View {
        MainTableView(viewModel: analyzer, embedded: true)
    }
}
