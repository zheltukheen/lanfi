import Foundation

struct LinkRateSample: Equatable, Identifiable {
    let at: Date
    let rateMbps: Double

    var id: Date { at }
}

/// Rate statistics for the connected link, sampled slowly so the inspector can
/// show a trend without a chart.
struct LinkTelemetrySummary: Equatable {
    let sampleCount: Int
    let rateMin: Double?
    let rateMax: Double?
    let rateAverage: Double?
    let latest: LinkRateSample?

    static let empty = LinkTelemetrySummary(
        sampleCount: 0, rateMin: nil, rateMax: nil, rateAverage: nil, latest: nil)

    static func make(samples: [LinkRateSample]) -> LinkTelemetrySummary {
        guard !samples.isEmpty else { return .empty }
        let rates = samples.map(\.rateMbps)
        let total = rates.reduce(0, +)
        return LinkTelemetrySummary(
            sampleCount: samples.count,
            rateMin: rates.min(),
            rateMax: rates.max(),
            rateAverage: total / Double(rates.count),
            latest: samples.max { $0.at < $1.at }
        )
    }
}

enum LinkTelemetryPresentation {
    /// CoreWLAN does not expose MCS or NSS for the live link, so the value comes
    /// from the beacon's spatial-streams and must be labelled as capability.
    static func nssCapability(streams: Int?) -> String {
        guard let streams, streams > 0 else { return "—" }
        return "\(streams) stream\(streams == 1 ? "" : "s") (capability)"
    }

    static func rate(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return String(format: "%.0f Mbps", value)
    }

    static func width(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        return "\(value) MHz"
    }
}
