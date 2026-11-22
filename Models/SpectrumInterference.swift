import Foundation

/// P2 — interferer classification for a sweep. The classifier works on any
/// `SpectrumSweep` (RF Explorer live, Wi-Spy/Chanalyzer CSV, remote WLAN Pi or
/// NetAlly export), so a source does not need its own analysis pipeline.
struct SpectrumInterferer: Identifiable, Equatable {
    let id: String
    let kind: SpectrumInterfererKind
    let frequencyMHz: Double
    let levelDBM: Double
    let widthMHz: Double
    let confidence: SpectrumConfidence
}

enum SpectrumInterfererKind: String, Equatable {
    case wifi
    case narrowband24
    case microwave
    case cordless
    case video
    case wideband
    case unknown

    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .narrowband24: return "Narrowband 2.4 GHz (Bluetooth/Zigbee)"
        case .microwave: return "Microwave oven"
        case .cordless: return "Cordless phone / DECT"
        case .video: return "Video / wideband"
        case .wideband: return "Wideband noise"
        case .unknown: return "Unclassified"
        }
    }
}

enum SpectrumConfidence: String, Equatable {
    case low, medium, high
}

enum SpectrumClassifier {
    /// Finds lobes at least 6 dB above the sweep median, merges adjacent bins,
    /// then labels each lobe by frequency and width. Heuristic, not a
    /// signature database; the label is a hint with a confidence.
    static func classify(_ sweep: SpectrumSweep, maxLobes: Int = 6) -> [SpectrumInterferer] {
        guard sweep.pointCount >= 3, let peak = sweep.amplitudes.max() else { return [] }
        let sorted = sweep.amplitudes.sorted()
        let median = sorted[sorted.count / 2]
        let threshold = max(median + 6, peak - 25)
        guard peak > threshold else { return [] }

        var lobes: [(start: Int, end: Int, peak: Double)] = []
        var current: (start: Int, end: Int, peak: Double)?
        for (index, level) in sweep.amplitudes.enumerated() {
            if level >= threshold {
                if var running = current {
                    running.end = index
                    running.peak = max(running.peak, level)
                    current = running
                } else {
                    current = (index, index, level)
                }
            } else if let running = current {
                lobes.append(running)
                current = nil
            }
        }
        if let running = current { lobes.append(running) }

        return
            lobes
            .sorted { $0.peak > $1.peak }
            .prefix(maxLobes)
            .enumerated()
            .map { offset, lobe in
                let startMHz = sweep.frequencyMHz(at: lobe.start)
                let endMHz = sweep.frequencyMHz(at: lobe.end)
                let width = max(0, endMHz - startMHz + sweep.stepMHz)
                let center = (startMHz + endMHz) / 2
                let (kind, confidence) = label(centerMHz: center, widthMHz: width)
                return SpectrumInterferer(
                    id: "\(offset)-\(Int(center))", kind: kind, frequencyMHz: center,
                    levelDBM: lobe.peak, widthMHz: width, confidence: confidence)
            }
    }

    static func label(
        centerMHz: Double, widthMHz: Double
    ) -> (SpectrumInterfererKind, SpectrumConfidence) {
        if centerMHz >= 2400, centerMHz <= 2500 {
            if widthMHz >= 40, centerMHz >= 2420, centerMHz <= 2480 {
                return (.microwave, widthMHz >= 60 ? .high : .medium)
            }
            if widthMHz >= 15 {
                return (.wifi, widthMHz >= 18 ? .high : .medium)
            }
            return (.narrowband24, widthMHz <= 3 ? .medium : .low)
        }
        if centerMHz >= 5150, centerMHz <= 5925 {
            return (.wifi, widthMHz >= 15 ? .high : .medium)
        }
        if centerMHz >= 1880, centerMHz <= 1930 {
            return (.cordless, .medium)
        }
        if centerMHz >= 900, centerMHz <= 930 {
            return (.cordless, .low)
        }
        if widthMHz >= 60 {
            return (.wideband, .low)
        }
        if centerMHz >= 5800, centerMHz <= 5900 {
            return (.video, .low)
        }
        return (.unknown, .low)
    }
}

/// The three hardware families the hub knows about, and what LanFi can
/// actually do with each without shipping a vendor USB driver.
enum SpectrumSourceKind: String, CaseIterable, Identifiable {
    case rfExplorer
    case wispy
    case wlanPi
    case netAlly
    case csvImport

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rfExplorer: return "RF Explorer"
        case .wispy: return "Wi-Spy"
        case .wlanPi: return "WLAN Pi (remote)"
        case .netAlly: return "NetAlly NXT-2000"
        case .csvImport: return "CSV trace"
        }
    }

    var capability: String {
        switch self {
        case .rfExplorer: return "Live USB-serial sweep"
        case .wispy: return "USB detection; import a Chanalyzer CSV"
        case .wlanPi: return "Remote CSV/JSON sweep over HTTP"
        case .netAlly: return "Import an AirCheck/NXT CSV export"
        case .csvImport: return "Any frequency/dBm table"
        }
    }
}
