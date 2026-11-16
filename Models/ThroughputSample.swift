import Foundation

/// Cumulative byte counters for one interface, as read from `getifaddrs`.
struct InterfaceCounters: Equatable {
    var receivedBytes: UInt64
    var sentBytes: UInt64
}

/// One smoothed throughput observation. Rates are bytes per second so the UI
/// can render bit/s or byte/s without re-deriving them.
struct ThroughputSample: Equatable, Identifiable {
    let at: Date
    let receivedBytesPerSecond: Double
    let sentBytesPerSecond: Double

    var id: Date { at }
    var totalBytesPerSecond: Double { receivedBytesPerSecond + sentBytesPerSecond }
}

enum ThroughputRate {
    /// Rate between two counter snapshots. A counter that went backwards is a
    /// reset (interface flap, sleep/wake), so the interval contributes zero
    /// instead of a nonsense spike.
    static func sample(
        previous: InterfaceCounters,
        previousAt: Date,
        current: InterfaceCounters,
        now: Date
    ) -> ThroughputSample? {
        let interval = now.timeIntervalSince(previousAt)
        guard interval > 0 else { return nil }
        let received =
            current.receivedBytes >= previous.receivedBytes
            ? Double(current.receivedBytes - previous.receivedBytes) / interval : 0
        let sent =
            current.sentBytes >= previous.sentBytes
            ? Double(current.sentBytes - previous.sentBytes) / interval : 0
        return ThroughputSample(
            at: now, receivedBytesPerSecond: received, sentBytesPerSecond: sent)
    }
}

/// Exponential moving average that keeps the menu-bar number from flickering
/// without hiding a real change for more than a few samples.
struct ThroughputSmoother {
    let alpha: Double
    private(set) var latest: ThroughputSample?

    init(alpha: Double = 0.4) {
        self.alpha = min(1, max(0.05, alpha))
    }

    mutating func add(_ sample: ThroughputSample) -> ThroughputSample {
        guard let previous = latest else {
            latest = sample
            return sample
        }
        let smoothed = ThroughputSample(
            at: sample.at,
            receivedBytesPerSecond: previous.receivedBytesPerSecond
                + (sample.receivedBytesPerSecond - previous.receivedBytesPerSecond) * alpha,
            sentBytesPerSecond: previous.sentBytesPerSecond
                + (sample.sentBytesPerSecond - previous.sentBytesPerSecond) * alpha
        )
        latest = smoothed
        return smoothed
    }

    mutating func reset() {
        latest = nil
    }
}

enum ThroughputFormatter {
    enum Unit: String, CaseIterable, Identifiable, Sendable {
        case bits
        case bytes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bits: return String(localized: "bit/s")
            case .bytes: return String(localized: "byte/s")
            }
        }
    }

    /// `12.4 Mbit/s`, `820 kbit/s`, `3.0 MB/s`, `0 bit/s`.
    static func rate(_ bytesPerSecond: Double, unit: Unit) -> String {
        let value = unit == .bits ? max(0, bytesPerSecond) * 8 : max(0, bytesPerSecond)
        let labels =
            unit == .bits
            ? ["bit/s", "kbit/s", "Mbit/s", "Gbit/s", "Tbit/s"]
            : ["B/s", "kB/s", "MB/s", "GB/s", "TB/s"]

        var scaled = value
        var index = 0
        while scaled >= 1000, index < labels.count - 1 {
            scaled /= 1000
            index += 1
        }
        guard index > 0 else { return String(format: "%.0f %@", scaled, labels[index]) }
        if scaled < 10 {
            return String(format: "%.1f %@", scaled, labels[index])
        }
        return String(format: "%.0f %@", scaled, labels[index])
    }

    /// Short form for the menu-bar label: `1.2M`, `820k`, `42`.
    static func compact(_ bytesPerSecond: Double, unit: Unit) -> String {
        let value = unit == .bits ? max(0, bytesPerSecond) * 8 : max(0, bytesPerSecond)
        let suffixes = ["", "k", "M", "G", "T"]
        var scaled = value
        var index = 0
        while scaled >= 1000, index < suffixes.count - 1 {
            scaled /= 1000
            index += 1
        }
        let number: String
        if index == 0 {
            number = String(format: "%.0f", scaled)
        } else if scaled < 10 {
            number = String(format: "%.1f", scaled)
        } else {
            number = String(format: "%.0f", scaled)
        }
        return number + suffixes[index]
    }
}
