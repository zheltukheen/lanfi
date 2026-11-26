import Foundation

/// Bounds a live capture so a busy channel cannot fill the disk, and decides
/// whether data-frame payloads are kept.
struct CaptureLimits: Codable, Equatable {
    /// Rotate the capture file every N million bytes (tcpdump `-C`).
    var maxFileSizeMB: Int?
    /// Truncate each data frame to this many captured bytes, keeping every
    /// management and control frame whole. Nil keeps full frames.
    var sliceDataFrameBytes: Int?

    static let none = CaptureLimits()

    static let sizeChoices: [Int] = [50, 100, 250, 500]
    static let sliceChoices: [Int] = [128, 256, 512]

    var rotates: Bool {
        guard let maxFileSizeMB else { return false }
        return maxFileSizeMB > 0
    }

    var slicesDataFrames: Bool {
        guard let sliceDataFrameBytes else { return false }
        return sliceDataFrameBytes > 0
    }

    /// `tcpdump` arguments for the size cap. Rotation is size-based on purpose:
    /// time-based rotation needs a strftime name, which would break the single
    /// output path the rest of the app (analysis, MCP, profiles) depends on.
    var tcpdumpArguments: [String] {
        guard let maxFileSizeMB, maxFileSizeMB > 0 else { return [] }
        return ["-C", "\(maxFileSizeMB)"]
    }

    var sizeLabel: String {
        guard let maxFileSizeMB, maxFileSizeMB > 0 else {
            return String(localized: "Single file")
        }
        return String(localized: "\(maxFileSizeMB) MB per file")
    }

    var sliceLabel: String {
        guard let sliceDataFrameBytes, sliceDataFrameBytes > 0 else {
            return String(localized: "Keep full frames")
        }
        return String(localized: "Data frames ≤ \(sliceDataFrameBytes) bytes")
    }
}

/// One channel to listen on. The band is optional because a channel typed by
/// hand may match numbers in two bands; when it is known the tuner picks the
/// right radio instead of the first channel with that number.
struct CaptureChannelRef: Equatable {
    let band: WiFiBand?
    let channel: Int
}

/// Which channels a capture listens on and how long it stays on each one.
/// A single channel pins the interface; a longer list is tuned by the app while
/// tcpdump runs, exactly like the passive scan engine does.
struct CaptureChannelPlan: Equatable {
    let channels: [CaptureChannelRef]
    let dwellMilliseconds: Int

    static let dwellChoices = [100, 150, 250, 500]
    static let minimumDwellMilliseconds = 50
    static let maximumDwellMilliseconds = 1000

    init(channels: [CaptureChannelRef], dwellMilliseconds: Int = 150) {
        var seen = Set<String>()
        self.channels = channels.filter { ref in
            guard (1...233).contains(ref.channel) else { return false }
            let bandKey = ref.band.map { String($0.rawValue) } ?? "-"
            return seen.insert("\(bandKey)-\(ref.channel)").inserted
        }
        self.dwellMilliseconds = min(
            max(dwellMilliseconds, Self.minimumDwellMilliseconds),
            Self.maximumDwellMilliseconds)
    }

    init(channels: [Int], dwellMilliseconds: Int = 150) {
        self.init(
            channels: channels.map { CaptureChannelRef(band: nil, channel: $0) },
            dwellMilliseconds: dwellMilliseconds)
    }

    var isHopping: Bool { channels.count > 1 }

    var cycleSeconds: TimeInterval {
        Double(channels.count * dwellMilliseconds) / 1000
    }

    /// The channel the plan listens on at `elapsed` seconds, or nil when the
    /// plan has nothing to tune.
    func channel(atElapsed elapsed: TimeInterval) -> CaptureChannelRef? {
        guard !channels.isEmpty else { return nil }
        guard dwellMilliseconds > 0 else { return channels.first }
        // Integer milliseconds avoid 0.3 / 0.1 landing on 2.999… and skipping
        // the last channel of the cycle.
        let elapsedMilliseconds = Int((max(0, elapsed) * 1000).rounded())
        let index = (elapsedMilliseconds / dwellMilliseconds) % channels.count
        return channels[index]
    }
}
