import Foundation

/// Row height presets for the AppKit network table. The raw value is the row
/// height in points, which is exactly what `AppSettings.rowDensity` stores, so
/// existing persisted values keep working without a migration.
enum TableDensity: Double, CaseIterable, Identifiable {
    case compact = 24
    case regular = 30
    case comfortable = 38

    var id: Double { rawValue }

    var rowHeight: Double { rawValue }

    /// Font size that keeps roughly the same optical padding at every height.
    /// `regular` matches the AppKit default text size so nothing shifts for
    /// users who never touch the setting.
    var fontSize: Double {
        switch self {
        case .compact: return 12
        case .regular: return 13
        case .comfortable: return 14
        }
    }

    var title: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .regular: return String(localized: "Standard")
        case .comfortable: return String(localized: "Roomy")
        }
    }

    /// Closest preset for a persisted height, defaulting to the standard row.
    static func resolve(rowHeight: Double) -> TableDensity {
        guard rowHeight > 0 else { return .regular }
        return allCases.min { abs($0.rawValue - rowHeight) < abs($1.rawValue - rowHeight) } ?? .regular
    }
}

// MARK: - Micro visuals

enum MicroVisualTint: Equatable {
    case ok
    case warning
    case danger
}

/// A bar painted beside a numeric table value.
///
/// **Product rule — do not widen this.** In-cell micro visuals exist only for
/// the Signal and Quality columns. Do not add bars, chips, badges or any other
/// in-cell decoration to Band, Security or any other column: categorical values
/// are already legible as text, the decoration reads as a second, competing
/// legend, and it made the table noisy. A bar must always sit *beside* its
/// number, never underneath it.
struct TableMicroVisual: Equatable {
    enum Shape: Equatable {
        /// A horizontal fill bar, `fraction` clamped to 0...1.
        case bar(fraction: Double)
    }

    let shape: Shape
    let tint: MicroVisualTint
}

enum TableMicroVisualFactory {
    /// Signal maps −95…−30 dBm onto 0…1 and grades at the same thresholds the
    /// table already uses for noisy links; Quality maps the 0–100 score.
    ///
    /// Every other column deliberately returns `nil` — see the product rule on
    /// `TableMicroVisual`.
    static func visual(
        for column: ColumnId, network: NetworkModel, qualityScore: Int?
    ) -> TableMicroVisual? {
        switch column {
        case .signal:
            let fraction = min(1, max(0, (Double(network.signal) + 95) / 65))
            let tint: MicroVisualTint =
                fraction >= 0.62 ? .ok : fraction >= 0.38 ? .warning : .danger
            return TableMicroVisual(shape: .bar(fraction: fraction), tint: tint)
        case .quality:
            guard let qualityScore else { return nil }
            let clamped = max(0, min(100, qualityScore))
            return TableMicroVisual(
                shape: .bar(fraction: Double(clamped) / 100),
                tint: tint(forQuality: clamped)
            )
        case .band, .bssid, .security, .apName, .amendments, .annotations, .basicRates, .beaconAirtime,
            .beaconInterval, .beaconMode, .beaconRate, .centerFrequency, .channel,
            .channelUtilization, .channelWidth, .clients, .congestion, .count, .countryCode,
            .fastTransition, .firstSeen, .generation, .ieCount, .ieTotalLength, .lastSeen,
            .maxBasicRate, .maxRate, .minBasicRate, .minRate, .mode, .networkName, .noise,
            .protectionMode, .puncturing, .seen, .snr, .ssidOverhead, .stations, .streams,
            .type, .uptime, .vendor, .wideChannel:
            return nil
        }
    }

    static func tint(forQuality score: Int) -> MicroVisualTint {
        switch QualityGrade(score: score) {
        case .excellent, .good: return .ok
        case .fair: return .warning
        case .poor: return .danger
        }
    }
}

/// Header decoration.
///
/// The sort indicator is drawn by AppKit from the table's sort descriptor, so
/// this only adds the active-grouping marker; adding an arrow here as well
/// produced two competing arrows in the same header.
enum TableHeaderDecoration {
    static func title(base: String, isGrouped: Bool) -> String {
        isGrouped ? base + " · " + String(localized: "grouped") : base
    }
}
