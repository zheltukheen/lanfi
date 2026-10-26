import Foundation

/// Pure formatting and comparison for every table column. Keeping this out of
/// the view model makes the full column catalog testable without CoreWLAN,
/// AppKit or a running app.
struct NetworkColumnFormatter {
    let signalDisplayMode: SignalDisplayMode
    let connectedBSSID: String?
    let metricsByNetworkId: [String: NetworkMetrics]

    // MARK: - Cell values

    func text(for column: ColumnId, network: NetworkModel) -> String {
        switch column {
        case .apName: return apName(for: network)
        case .amendments: return network.generationLabel
        case .annotations: return annotations(for: network)
        case .bssid: return network.bssid.isEmpty ? "-" : network.bssid
        case .band: return network.bandLabel
        case .basicRates: return network.basicRatesLabel
        case .beaconAirtime: return formatOptionalDouble(network.beaconAirtime)
        case .beaconInterval: return formatOptionalInt(network.beaconInterval)
        case .beaconMode: return network.beaconMode ?? network.mode
        case .beaconRate: return formatOptionalDouble(network.beaconRate)
        case .centerFrequency: return network.centerFrequencyLabel
        case .channel: return "\(network.channel)"
        case .channelUtilization: return formatOptionalInt(network.channelUtilization)
        case .channelWidth: return network.channelWidthLabel
        case .clients: return formatOptionalInt(network.clients)
        case .congestion: return metrics(for: network)?.congestionScore.description ?? "-"
        case .count: return "\(network.count)"
        case .countryCode: return network.countryCode ?? "-"
        case .fastTransition: return formatOptionalBool(network.fastTransition)
        case .firstSeen: return formatDate(network.firstSeen)
        case .generation: return network.generationLabel
        case .ieCount: return formatOptionalInt(network.ieCount)
        case .ieTotalLength: return formatOptionalInt(network.ieTotalLength)
        case .lastSeen: return formatDate(network.lastSeen)
        case .maxBasicRate: return network.maxBasicRateLabel
        case .maxRate: return network.maxRateLabel
        case .minBasicRate: return network.minBasicRateLabel
        case .minRate: return network.minRateLabel
        case .mode: return network.mode
        case .networkName: return network.displaySSID
        case .noise: return network.noiseLabel
        case .protectionMode: return network.protectionMode ?? "-"
        case .quality: return metrics(for: network)?.qualityScore.description ?? "-"
        case .security: return network.security
        case .seen: return "\(network.seen)"
        case .signal: return Self.formatSignal(network.signal, mode: signalDisplayMode)
        case .snr: return network.snrLabel
        case .stations: return formatOptionalInt(network.stations)
        case .streams: return formatOptionalInt(network.streams)
        case .type: return network.type ?? "-"
        case .uptime: return network.uptimeSeconds.map(formatDuration(seconds:)) ?? "-"
        case .vendor: return network.vendor
        case .wideChannel: return network.wideChannelLabel
        }
    }

    // MARK: - Sorting

    func compare(_ first: NetworkModel, _ second: NetworkModel, by column: ColumnId) -> Bool {
        switch column {
        case .apName:
            return compareText(apName(for: first), apName(for: second))
        case .amendments:
            return first.generation.sortOrder < second.generation.sortOrder
        case .annotations:
            return compareText(annotations(for: first), annotations(for: second))
        case .bssid:
            return compareText(first.bssid, second.bssid)
        case .band:
            return first.band.sortOrder < second.band.sortOrder
        case .basicRates:
            return compareOptional(first.maxBasicRate, second.maxBasicRate)
        case .beaconAirtime:
            return compareOptional(first.beaconAirtime, second.beaconAirtime)
        case .beaconInterval:
            return compareOptional(first.beaconInterval, second.beaconInterval)
        case .beaconMode:
            return compareText(first.beaconMode ?? first.mode, second.beaconMode ?? second.mode)
        case .beaconRate:
            return compareOptional(first.beaconRate, second.beaconRate)
        case .centerFrequency:
            return compareOptional(first.centerFrequency, second.centerFrequency)
        case .channel:
            return first.channel < second.channel
        case .channelUtilization:
            return compareOptional(first.channelUtilization, second.channelUtilization)
        case .channelWidth:
            return first.channelWidthMHz < second.channelWidthMHz
        case .clients:
            return compareOptional(first.clients, second.clients)
        case .congestion:
            return compareOptional(metrics(for: first)?.congestionScore, metrics(for: second)?.congestionScore)
        case .count:
            return first.count < second.count
        case .countryCode:
            return compareText(first.countryCode ?? "", second.countryCode ?? "")
        case .fastTransition:
            return boolToInt(first.fastTransition) < boolToInt(second.fastTransition)
        case .firstSeen:
            return compareDates(first.firstSeen, second.firstSeen)
        case .generation:
            return first.generation.sortOrder < second.generation.sortOrder
        case .ieCount:
            return compareOptional(first.ieCount, second.ieCount)
        case .ieTotalLength:
            return compareOptional(first.ieTotalLength, second.ieTotalLength)
        case .lastSeen:
            return compareDates(first.lastSeen, second.lastSeen)
        case .maxBasicRate:
            return compareOptional(first.maxBasicRate, second.maxBasicRate)
        case .maxRate:
            return compareOptional(first.maxRate, second.maxRate)
        case .minBasicRate:
            return compareOptional(first.minBasicRate, second.minBasicRate)
        case .minRate:
            return compareOptional(first.minRate, second.minRate)
        case .mode:
            return compareText(first.mode, second.mode)
        case .networkName:
            return compareText(first.displaySSID, second.displaySSID)
        case .noise:
            return compareOptional(first.noise, second.noise)
        case .protectionMode:
            return compareText(first.protectionMode ?? "", second.protectionMode ?? "")
        case .quality:
            return compareOptional(metrics(for: first)?.qualityScore, metrics(for: second)?.qualityScore)
        case .security:
            return compareText(first.security, second.security)
        case .seen:
            return first.seen < second.seen
        case .signal:
            return first.signal < second.signal
        case .snr:
            return compareOptional(first.snr, second.snr)
        case .stations:
            return compareOptional(first.stations, second.stations)
        case .streams:
            return compareOptional(first.streams, second.streams)
        case .type:
            return compareText(first.type ?? "", second.type ?? "")
        case .uptime:
            return compareOptional(first.uptimeSeconds, second.uptimeSeconds)
        case .vendor:
            return compareText(first.vendor, second.vendor)
        case .wideChannel:
            return (first.channelWidthMHz >= 80 ? 1 : 0) < (second.channelWidthMHz >= 80 ? 1 : 0)
        }
    }

    // MARK: - Signal formatting

    static func formatSignal(_ dbm: Int, mode: SignalDisplayMode) -> String {
        switch mode {
        case .dbm:
            return "\(dbm)"
        case .percent:
            let quality = max(0, min(100, (dbm + 100) * 2))
            return "\(quality)%"
        }
    }

    // MARK: - Private helpers

    private func metrics(for network: NetworkModel) -> NetworkMetrics? {
        metricsByNetworkId[network.id]
    }

    private func apName(for network: NetworkModel) -> String {
        network.vendor != "-" ? network.vendor : network.displaySSID
    }

    private func annotations(for network: NetworkModel) -> String {
        var parts: [String] = []
        if network.ssid.isEmpty { parts.append("Hidden SSID") }
        if network.ratesEstimated { parts.append("Est. rates") }
        if let connectedBSSID, !connectedBSSID.isEmpty, network.bssid == connectedBSSID {
            parts.append("Connected")
        }
        if let metric = metrics(for: network) {
            if metric.grade == .poor { parts.append("Poor quality") }
            if metric.interferenceLoad >= 0.5 { parts.append("Congested") }
        }
        if network.security.lowercased().contains("open") { parts.append("Open") }
        return parts.isEmpty ? "-" : parts.joined(separator: ", ")
    }

    private func compareText(_ first: String, _ second: String) -> Bool {
        first.localizedCaseInsensitiveCompare(second) == .orderedAscending
    }

    private func compareOptional<T: Comparable>(_ first: T?, _ second: T?) -> Bool {
        switch (first, second) {
        case let (first?, second?): return first < second
        case (nil, .some): return true
        case (.some, nil): return false
        case (nil, nil): return false
        }
    }

    private func compareDates(_ first: Date?, _ second: Date?) -> Bool {
        compareOptional(first, second)
    }

    private func boolToInt(_ value: Bool?) -> Int {
        value == true ? 1 : 0
    }

    private func formatOptionalInt(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    private func formatOptionalDouble(_ value: Double?) -> String {
        guard let value else { return "-" }
        if value == 0 { return "0" }
        if abs(value) < 10 { return String(format: "%.1f", value) }
        return String(format: "%.0f", value)
    }

    private func formatOptionalBool(_ value: Bool?) -> String {
        guard let value else { return "-" }
        return value ? "Yes" : "No"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return Self.dateFormatter.string(from: date)
    }

    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%02dh %02dm %02ds", hours, minutes, secs)
        }
        if minutes > 0 {
            return String(format: "%02dm %02ds", minutes, secs)
        }
        return "\(secs)s"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
