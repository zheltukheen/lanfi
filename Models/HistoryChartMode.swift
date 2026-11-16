import Foundation

/// What the signal-history chart plots. Noise is not meaningful in percent
/// mode, so the view falls back to `signal` when the display unit is percent.
enum HistoryChartMode: String, CaseIterable, Identifiable {
    case signal
    case noise
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signal: return String(localized: "Signal")
        case .noise: return String(localized: "Noise")
        case .both: return String(localized: "Both")
        }
    }

    var showsSignal: Bool { self != .noise }

    var showsNoise: Bool { self != .signal }
}
