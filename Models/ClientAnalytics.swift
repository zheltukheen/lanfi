import Foundation

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

    init(
        mac: String, bssid: String, vendor: String, rssi: Int?, frames: Int, probes: [String] = []
    ) {
        self.id = mac + "|" + bssid
        self.mac = mac
        self.bssid = bssid
        self.vendor = vendor
        self.rssi = rssi
        self.frames = frames
        self.probes = probes
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

    let advertisedClients: Int
    let accessPointCount: Int
    let capturedClients: Int
    let capturedFrames: Int
    let averageCapturedRSSI: Int?
    let busiestAccessPoints: [AccessPointLoad]
    let idleAccessPoints: Int
    let vendorMix: [ValueCount]
    let probeSSIDs: [ValueCount]
    let insights: [String]

    static func build(
        networks: [NetworkModel], observations: [ClientObservation] = []
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
            insights: insights
        )
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }
}
