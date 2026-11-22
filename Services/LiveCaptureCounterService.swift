import Foundation

/// Tails the pcap tcpdump is writing and republishes deauth/disassoc/EAPOL
/// counters once a second. Read-only: the file is mapped, never modified, and
/// parsing stops as soon as the capture view calls `stop()`.
@MainActor
final class LiveCaptureCounterModel: ObservableObject {
    @Published private(set) var snapshot: LiveThreatSnapshot = .empty
    @Published private(set) var isMonitoring = false

    private var timer: Timer?
    private var fileURL: URL?
    private var lastSize = -1
    private var isParsing = false

    func start(url: URL) {
        stop()
        fileURL = url
        lastSize = -1
        snapshot = .empty
        isMonitoring = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        fileURL = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func poll() async {
        guard isMonitoring, !isParsing, let fileURL else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 24, size != lastSize else { return }
        lastSize = size
        isParsing = true
        defer { isParsing = false }
        let report = await Task.detached(priority: .utility) { () -> CaptureSecurityReport? in
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
                return nil
            }
            return try? PcapAnalyzer.securityReport(data: data)
        }.value
        guard let report else { return }
        snapshot = LiveThreatSnapshot.make(report: report, bytes: size)
    }
}
