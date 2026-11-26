import Foundation
import LanFiCore

/// One client seen during a monitor capture, decoupled from the pcap parser so
/// the aggregation stays pure and testable.
struct ClientObservation: Identifiable, Equatable {
    let id: String
    let mac: String
    let bssid: String
    let vendor: String
    let rssi: Int?
    let frames: Int
    let probes: [String]
    /// Frames retransmitted by this client (802.11 Retry bit).
    let retries: Int
    /// Airtime this client reserved, summed from the Duration/ID fields.
    let airtimeMicroseconds: Int
    let firstSeen: Date?
    let lastSeen: Date?
    /// G8: capabilities from its association request, or the AP beacon fallback.
    let capabilities: ClientCapabilitySummary?

    init(
        mac: String, bssid: String, vendor: String, rssi: Int?, frames: Int,
        probes: [String] = [], retries: Int = 0, airtimeMicroseconds: Int = 0,
        firstSeen: Date? = nil, lastSeen: Date? = nil,
        capabilities: ClientCapabilitySummary? = nil
    ) {
        self.id = mac + "|" + bssid
        self.mac = mac
        self.bssid = bssid
        self.vendor = vendor
        self.rssi = rssi
        self.frames = frames
        self.probes = probes
        self.retries = retries
        self.airtimeMicroseconds = airtimeMicroseconds
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.capabilities = capabilities
    }
}

/// P1.3 client analytics: combines the client counts access points advertise in
/// their beacons with optional captured client frames into one report.
struct ClientAnalyticsSnapshot: Equatable {
    struct AccessPointLoad: Identifiable, Equatable {
        let bssid: String
        let ssid: String
        let band: String
        let channel: Int
        let clients: Int
        let utilization: Int?
        let signal: Int

        var id: String { bssid }
        var loadLabel: String { "\(clients)" }
    }

    struct ValueCount: Identifiable, Equatable {
        let value: String
        let count: Int

        var id: String { value }
    }

    /// P1.3 capture accounting: what one client actually cost the medium.
    struct ClientLoad: Identifiable, Equatable {
        let mac: String
        let vendor: String
        let frames: Int
        let retries: Int
        let airtimeMicroseconds: Int
        /// Airtime as a fraction of all captured airtime, when the capture
        /// carried any duration values at all.
        let airtimeShare: Double?

        var id: String { mac }
        var retryRate: Double? { frames > 0 ? Double(retries) / Double(frames) : nil }
        var airtimeMilliseconds: Int { airtimeMicroseconds / 1000 }
    }

    let advertisedClients: Int
    let accessPointCount: Int
    let capturedClients: Int
    let capturedFrames: Int
    let averageCapturedRSSI: Int?
    let busiestAccessPoints: [AccessPointLoad]
    let idleAccessPoints: Int
    let vendorMix: [ValueCount]
    let probeSSIDs: [ValueCount]
    /// Per-client airtime and retry accounting, busiest first.
    let clientLoads: [ClientLoad]
    let totalAirtimeMicroseconds: Int
    /// G7: transmitter-side airtime per BSSID, busiest first.
    let channelAirtime: [ChannelAirtimeEntry]
    let insights: [String]

    static func build(
        networks: [NetworkModel], observations: [ClientObservation] = [],
        channelAirtime: [ChannelAirtimeEntry] = []
    ) -> ClientAnalyticsSnapshot {
        let loads =
            networks
            .filter { ($0.clients ?? 0) > 0 || ($0.stations ?? 0) > 0 }
            .map { network in
                AccessPointLoad(
                    bssid: network.bssid,
                    ssid: network.displaySSID,
                    band: network.bandLabel,
                    channel: network.channel,
                    clients: network.clients ?? network.stations ?? 0,
                    utilization: network.channelUtilization,
                    signal: network.signal
                )
            }
            .sorted { lhs, rhs in
                if lhs.clients != rhs.clients { return lhs.clients > rhs.clients }
                return lhs.ssid.localizedStandardCompare(rhs.ssid) == .orderedAscending
            }

        let uniqueClients = Set(observations.map(\.mac))
        let rssiValues = observations.compactMap(\.rssi)
        let frames = observations.reduce(0) { $0 + $1.frames }

        var vendorCounts: [String: Int] = [:]
        for observation in observations {
            let vendor = observation.vendor.isEmpty ? "Unknown" : observation.vendor
            vendorCounts[vendor, default: 0] += 1
        }
        let vendors = vendorCounts.map { ValueCount(value: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.value < rhs.value
            }

        var probeCounts: [String: Int] = [:]
        for observation in observations {
            for probe in Set(observation.probes) where !probe.isEmpty {
                probeCounts[probe, default: 0] += 1
            }
        }

        // A client can appear once per BSSID, so the accounting adds those
        // rows together before ranking: airtime belongs to the radio, not to
        // the association.
        struct LoadTotals {
            var vendor: String
            var frames = 0
            var retries = 0
            var airtime = 0
        }
        var totals: [String: LoadTotals] = [:]
        for observation in observations {
            var entry = totals[observation.mac] ?? LoadTotals(vendor: observation.vendor)
            entry.frames += observation.frames
            entry.retries += observation.retries
            entry.airtime += observation.airtimeMicroseconds
            if entry.vendor.isEmpty { entry.vendor = observation.vendor }
            totals[observation.mac] = entry
        }
        let totalAirtime = totals.values.reduce(0) { $0 + $1.airtime }
        let clientLoads = totals.map { mac, entry in
            ClientLoad(
                mac: mac,
                vendor: entry.vendor.isEmpty ? "Unknown" : entry.vendor,
                frames: entry.frames,
                retries: entry.retries,
                airtimeMicroseconds: entry.airtime,
                airtimeShare: totalAirtime > 0 ? Double(entry.airtime) / Double(totalAirtime) : nil
            )
        }
        .sorted { left, right in
            if left.airtimeMicroseconds != right.airtimeMicroseconds {
                return left.airtimeMicroseconds > right.airtimeMicroseconds
            }
            if left.frames != right.frames { return left.frames > right.frames }
            return left.mac < right.mac
        }
        let probes = probeCounts.map { ValueCount(value: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.value < rhs.value
            }

        let advertised = loads.reduce(0) { $0 + $1.clients }
        var insights: [String] = []
        if loads.isEmpty && networks.isEmpty {
            insights.append("No Wi-Fi scan data yet. Run a scan in the Wi-Fi Analyzer.")
        } else if loads.isEmpty {
            insights.append(
                "No access point advertises its client count. CoreWLAN exposes this only when the AP includes it in beacons."
            )
        }
        if let busiest = loads.first, busiest.clients >= 10 {
            insights.append(
                "\(busiest.ssid) advertises \(busiest.clients) clients on \(busiest.band) channel \(busiest.channel); consider load balancing or an extra AP."
            )
        }
        if let busiest = loads.first, let utilization = busiest.utilization, utilization >= 60 {
            insights.append(
                "\(busiest.ssid) reports \(utilization)% channel utilization. Latency will rise under load."
            )
        }
        if uniqueClients.count >= 3 {
            insights.append(
                "\(uniqueClients.count) unique client MACs seen. Randomised MACs inflate this count."
            )
        }
        if let probes = probes.first, probes.count >= 2 {
            insights.append(
                "Several clients probe for \(probes.value); that SSID may be remembered but out of range."
            )
        }
        if let average = average(rssiValues), average < -75 {
            insights.append(
                "Captured clients average \(average) dBm. They are far from the sensor, not necessarily from the AP."
            )
        }
        if let worst = clientLoads.first(where: { ($0.retryRate ?? 0) >= 0.1 && $0.frames >= 20 }) {
            let percent = Int(((worst.retryRate ?? 0) * 100).rounded())
            insights.append(
                "\(percent)% of \(worst.mac)'s frames were retries. That points at a weak uplink or a hidden interferer."
            )
        }
        if clientLoads.count >= 3, let busiest = clientLoads.first,
            let share = busiest.airtimeShare, share >= 0.4
        {
            insights.append(
                "One client used \(Int((share * 100).rounded()))% of the captured airtime. Throttling it would free the channel for everyone else."
            )
        }
        if channelAirtime.count >= 2, let top = channelAirtime.first,
            let share = top.share, share >= 0.4
        {
            insights.append(
                "\(top.ssid) (\(top.bssid)) reserved \(Int((share * 100).rounded()))% of the captured airtime. That is the access point to look at first, not the client list."
            )
        }
        if let legacy = channelAirtime.first(where: \.isLegacy) {
            insights.append(
                "\(legacy.ssid) sent \(legacy.legacyFrames) data frames at 802.11b rates. One legacy device keeps the whole channel slow."
            )
        } else if let network = networks.first(where: { LegacyWiFiDetector.flag($0) }),
            let summary = LegacyWiFiDetector.summary(for: network)
        {
            insights.append(summary)
        }

        return ClientAnalyticsSnapshot(
            advertisedClients: advertised,
            accessPointCount: networks.count,
            capturedClients: uniqueClients.count,
            capturedFrames: frames,
            averageCapturedRSSI: average(rssiValues),
            busiestAccessPoints: loads,
            idleAccessPoints: max(0, networks.count - loads.count),
            vendorMix: vendors,
            probeSSIDs: probes,
            clientLoads: clientLoads,
            totalAirtimeMicroseconds: totalAirtime,
            channelAirtime: channelAirtime,
            insights: insights
        )
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }
}
