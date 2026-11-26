import Foundation

// MARK: - Client capabilities

/// The PHY generations a client advertised. Ordered from oldest to newest so
/// the highest one can be shown as "the generation" without guessing.
public enum ClientPHY: String, CaseIterable, Sendable, Comparable {
    case b
    case a
    case g
    case n
    case ac
    case ax
    case be

    public var label: String {
        switch self {
        case .b: return "11b"
        case .a: return "11a"
        case .g: return "11g"
        case .n: return "11n"
        case .ac: return "11ac"
        case .ax: return "11ax"
        case .be: return "11be"
        }
    }

    public var rank: Int {
        switch self {
        case .b: return 0
        case .a: return 1
        case .g: return 2
        case .n: return 3
        case .ac: return 4
        case .ax: return 5
        case .be: return 6
        }
    }

    public static func < (lhs: ClientPHY, rhs: ClientPHY) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Where a capability summary came from. Association frames describe the
/// client itself; a beacon describes the client's access point, which is a
/// fallback and is labelled as one.
public enum ClientCapabilitySource: String, Sendable, Equatable {
    case associationRequest
    case reassociationRequest
    case beacon

    public var label: String {
        switch self {
        case .associationRequest: return "Association request"
        case .reassociationRequest: return "Reassociation request"
        case .beacon: return "AP beacon (fallback)"
        }
    }
}

/// G8: what a client's own association request (or, as a fallback, its AP's
/// beacon) says it supports. Only advertised values are kept; nothing is
/// inferred from the connection's current rate.
public struct ClientCapabilitySummary: Equatable, Sendable {
    public var phy: Set<ClientPHY>
    /// Widest MIMO order advertised by HT/VHT capabilities, when present.
    public var streams: Int?
    public var supportedRatesMbps: [Double]
    public var fastTransition: Bool
    public var pmfCapable: Bool
    public var source: ClientCapabilitySource

    public init(
        phy: Set<ClientPHY>, streams: Int? = nil, supportedRatesMbps: [Double] = [],
        fastTransition: Bool = false, pmfCapable: Bool = false,
        source: ClientCapabilitySource
    ) {
        self.phy = phy
        self.streams = streams
        self.supportedRatesMbps = supportedRatesMbps
        self.fastTransition = fastTransition
        self.pmfCapable = pmfCapable
        self.source = source
    }

    public var hasCapabilities: Bool {
        !phy.isEmpty || !supportedRatesMbps.isEmpty
    }

    public var generation: ClientPHY? { phy.max() }

    public var generationLabel: String { generation?.label ?? "—" }

    public var ratesLabel: String? {
        guard let low = supportedRatesMbps.first, let high = supportedRatesMbps.last else {
            return nil
        }
        if supportedRatesMbps.count <= 3 {
            return supportedRatesMbps.map(Self.formatRate).joined(separator: " / ")
                + " Mbit/s"
        }
        return "\(Self.formatRate(low))–\(Self.formatRate(high)) Mbit/s"
    }

    /// Short chips for a card header.
    public var capabilityLabels: [String] {
        var labels: [String] = []
        if let generation { labels.append(generation.label) }
        if let streams { labels.append("\(streams)×\(streams) MIMO") }
        if let ratesLabel { labels.append(ratesLabel) }
        if fastTransition { labels.append("802.11r FT") }
        if pmfCapable { labels.append("PMF capable") }
        return labels
    }

    public var summaryLine: String { capabilityLabels.joined(separator: " · ") }

    /// Decodes information elements from an association/reassociation request
    /// body or a beacon. Returns nil when the bytes contain no elements at all.
    public static func decode(
        ieBytes: Data, source: ClientCapabilitySource
    ) -> ClientCapabilitySummary? {
        guard !ieBytes.isEmpty else { return nil }
        var phy: Set<ClientPHY> = []
        var rates: [Double] = []
        var streams: Int?
        var fastTransition = false
        var pmfCapable = false
        var sawElement = false

        var index = ieBytes.startIndex
        let end = ieBytes.endIndex
        while index + 2 <= end {
            let id = Int(ieBytes[index])
            let length = Int(ieBytes[index + 1])
            let start = index + 2
            guard start + length <= end else { break }
            let payload = ieBytes[start..<(start + length)]
            index = start + length
            sawElement = true

            switch id {
            case 1, 50:
                for byte in payload {
                    let rate = Double(byte & 0x7F) * 0.5
                    if rate > 0 { rates.append(rate) }
                }
            case 45:
                phy.insert(.n)
                if let advertised = htStreams(payload) {
                    streams = max(streams ?? 0, advertised)
                }
            case 191:
                phy.insert(.ac)
                if let advertised = vhtStreams(payload) {
                    streams = max(streams ?? 0, advertised)
                }
            case 255:
                switch payload.first {
                case 35: phy.insert(.ax)
                case 106, 107: phy.insert(.be)
                default: break
                }
            case 54:
                fastTransition = true
            case 48:
                pmfCapable = rsnPMFCapable(payload)
            default:
                break
            }
        }

        guard sawElement else { return nil }
        let uniqueRates = Array(Set(rates)).sorted()
        // A rates-only association at 1–11 Mbit/s is an 802.11b client. Rates
        // alone cannot separate 11a from 11g, so neither is guessed.
        if !phy.contains(.n), let fastest = uniqueRates.last, fastest <= 11 {
            phy.insert(.b)
        }
        return ClientCapabilitySummary(
            phy: phy, streams: streams, supportedRatesMbps: uniqueRates,
            fastTransition: fastTransition, pmfCapable: pmfCapable, source: source)
    }

    private static func formatRate(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// HT Capabilities: 2 bytes of HT Cap Info, 1 byte of A-MPDU parameters,
    /// then a 16-byte supported MCS set whose first 4 bytes are the RX mask.
    private static func htStreams(_ payload: Data) -> Int? {
        let bytes = Array(payload)
        guard bytes.count >= 7 else { return nil }
        var mask: UInt32 = 0
        for offset in 0..<4 {
            mask |= UInt32(bytes[3 + offset]) << (8 * UInt32(offset))
        }
        guard mask != 0 else { return nil }
        let highest = 31 - mask.leadingZeroBitCount
        return min(4, highest / 8 + 1)
    }

    /// VHT Capabilities: 4 bytes of capability info, then eight 2-byte MCS
    /// maps (one per stream) where each 2-bit code 3 means "not supported".
    private static func vhtStreams(_ payload: Data) -> Int? {
        let bytes = Array(payload)
        guard bytes.count >= 12 else { return nil }
        var highest = 0
        for stream in 0..<4 {
            let map = UInt16(bytes[4 + stream * 2]) | UInt16(bytes[5 + stream * 2]) << 8
            // Every 2-bit code 3 means the stream carries no MCS at all.
            if map != 0xFFFF { highest = stream + 1 }
        }
        return highest > 0 ? highest : nil
    }

    /// RSN capabilities bit 7 is MFPC (management-frame protection capable).
    private static func rsnPMFCapable(_ payload: Data) -> Bool {
        let bytes = Array(payload)
        guard bytes.count >= 8 else { return false }
        var index = 2 + 4
        guard index + 2 <= bytes.count else { return false }
        let pairwise = Int(bytes[index]) | Int(bytes[index + 1]) << 8
        index += 2 + pairwise * 4
        guard index + 2 <= bytes.count else { return false }
        let akm = Int(bytes[index]) | Int(bytes[index + 1]) << 8
        index += 2 + akm * 4
        guard index + 2 <= bytes.count else { return false }
        let capabilities = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        return capabilities & 0x0080 != 0
    }
}

// MARK: - Signal locator

public struct SignalLocatorSample: Equatable, Sendable {
    public let rssi: Int
    public let timestamp: Date

    public init(rssi: Int, timestamp: Date) {
        self.rssi = rssi
        self.timestamp = timestamp
    }
}

public enum SignalProximity: String, Sendable, CaseIterable {
    case strong
    case good
    case fair
    case far
    case lost

    public var label: String {
        switch self {
        case .strong: return "Very strong"
        case .good: return "Good"
        case .fair: return "Fair"
        case .far: return "Weak"
        case .lost: return "Signal lost"
        }
    }

    public var advice: String {
        switch self {
        case .strong: return "You are close to the transmitter."
        case .good: return "Good signal. A few steps in either direction will show which way is better."
        case .fair: return "Move slowly; small position changes matter at this level."
        case .far: return "Weak signal. Keep moving and watch the readout."
        case .lost: return "No sample for a while. The device may be out of range, quiet, or off."
        }
    }

    public static func forRSSI(_ rssi: Double) -> SignalProximity {
        switch rssi {
        case ...(-75): return .far
        case ...(-67): return .fair
        case ...(-55): return .good
        default: return .strong
        }
    }
}

public struct SignalLocatorState: Equatable, Sendable {
    public var smoothedRSSI: Double?
    public var latestRSSI: Int?
    public var sampleCount: Int = 0
    public var lastSampleAt: Date?
    /// dBm per second over the smoothing window; positive means closing in.
    public var trendDBmPerSecond: Double?
    public var isLost: Bool = false

    public init(
        smoothedRSSI: Double? = nil, latestRSSI: Int? = nil, sampleCount: Int = 0,
        lastSampleAt: Date? = nil, trendDBmPerSecond: Double? = nil, isLost: Bool = false
    ) {
        self.smoothedRSSI = smoothedRSSI
        self.latestRSSI = latestRSSI
        self.sampleCount = sampleCount
        self.lastSampleAt = lastSampleAt
        self.trendDBmPerSecond = trendDBmPerSecond
        self.isLost = isLost
    }

    public var proximity: SignalProximity {
        guard !isLost, let smoothedRSSI else { return .lost }
        return SignalProximity.forRSSI(smoothedRSSI)
    }

    public var trendLabel: String? {
        guard let trendDBmPerSecond else { return nil }
        if trendDBmPerSecond >= 1.5 { return "Getting stronger" }
        if trendDBmPerSecond <= -1.5 { return "Getting weaker" }
        return "Steady"
    }
}

/// G8b: an exponential moving average over RSSI samples plus a signal-lost
/// timer. The caller decides how often to sample (the UI aims for 4 Hz, but a
/// CoreWLAN scan decides the real cadence); this type only cares about the
/// timestamps it is given.
public struct SignalLocator: Equatable, Sendable {
    public let smoothingFactor: Double
    public let lostAfter: TimeInterval
    public let trendWindow: TimeInterval

    private var samples: [SignalLocatorSample] = []
    private var smoothed: Double?
    public private(set) var state = SignalLocatorState()

    public init(
        smoothingFactor: Double = 0.25, lostAfter: TimeInterval = 3,
        trendWindow: TimeInterval = 8
    ) {
        self.smoothingFactor = min(max(smoothingFactor, 0.01), 1)
        self.lostAfter = max(lostAfter, 0.5)
        self.trendWindow = max(trendWindow, 1)
    }

    /// Adds one reading. Values outside the possible RSSI range are ignored so
    /// a CoreWLAN "0 means unknown" does not drag the average to zero.
    @discardableResult
    public mutating func ingest(rssi: Int, at timestamp: Date) -> SignalLocatorState {
        guard rssi < 0, rssi >= -120 else { return state }
        if let current = smoothed {
            smoothed = smoothingFactor * Double(rssi) + (1 - smoothingFactor) * current
        } else {
            smoothed = Double(rssi)
        }
        samples.append(SignalLocatorSample(rssi: rssi, timestamp: timestamp))
        let window = trendWindow
        samples.removeAll { timestamp.timeIntervalSince($0.timestamp) > window }
        state = SignalLocatorState(
            smoothedRSSI: smoothed, latestRSSI: rssi, sampleCount: state.sampleCount + 1,
            lastSampleAt: timestamp, trendDBmPerSecond: trend(), isLost: false)
        return state
    }

    /// Called when a sampling round produced no reading for the target, so the
    /// UI can say "lost" instead of showing a stale number.
    @discardableResult
    public mutating func tick(at timestamp: Date) -> SignalLocatorState {
        guard !state.isLost, let last = state.lastSampleAt,
            timestamp.timeIntervalSince(last) > lostAfter
        else { return state }
        // A recovered reading starts a fresh average: blending it with a
        // minutes-old value would report a signal that does not exist.
        smoothed = nil
        samples = []
        state = SignalLocatorState(
            smoothedRSSI: nil, latestRSSI: state.latestRSSI, sampleCount: state.sampleCount,
            lastSampleAt: state.lastSampleAt, trendDBmPerSecond: nil, isLost: true)
        return state
    }

    public mutating func reset() {
        samples = []
        smoothed = nil
        state = SignalLocatorState()
    }

    /// Least-squares slope over the window. Fewer than three samples, or less
    /// than a second of data, is not enough to call a trend.
    private func trend() -> Double? {
        guard samples.count >= 3, let first = samples.first, let last = samples.last
        else { return nil }
        guard last.timestamp.timeIntervalSince(first.timestamp) >= 1 else { return nil }
        let origin = first.timestamp
        let xs = samples.map { $0.timestamp.timeIntervalSince(origin) }
        let ys = samples.map { Double($0.rssi) }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for index in samples.indices {
            numerator += (xs[index] - meanX) * (ys[index] - meanY)
            denominator += (xs[index] - meanX) * (xs[index] - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
}
