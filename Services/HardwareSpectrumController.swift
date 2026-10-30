import Foundation

/// Connects an RF Explorer spectrum analyzer over its USB-serial port,
/// decodes live sweeps and publishes them to SwiftUI.
final class HardwareSpectrumController: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected(info: String)
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var latestSweep: SpectrumSweep?
    @Published private(set) var maxHoldSweep: SpectrumSweep?
    @Published var useMaxHold = true

    private let port = SerialPortConnection()
    private let parser = RFExplorerProtocol.StreamParser()
    private var config: RFExplorerProtocol.Config?

    static let shared = HardwareSpectrumController()

    var availablePorts: [String] { SerialPortConnection.availablePorts() }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var deviceInfo: String {
        guard case .connected(let info) = state else { return "" }
        return info
    }

    func connect(portPath: String) {
        disconnect()
        state = .connecting
        do {
            try port.open(path: portPath)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        port.startReading { [weak self] bytes in
            guard let self else { return }
            let events = self.parser.append(bytes)
            let sweeps: [(SpectrumSweep, RFExplorerProtocol.Config)] = events.compactMap { event in
                guard case .sweep(let amplitudes, let config) = event else { return nil }
                return (
                    SpectrumSweep(
                        source: "RF Explorer",
                        capturedAt: Date(),
                        startMHz: config.startMHz,
                        stepMHz: config.stepMHz,
                        amplitudes: amplitudes
                    ),
                    config
                )
            }
            let configs = events.compactMap { event -> RFExplorerProtocol.Config? in
                guard case .config(let config) = event else { return nil }
                return config
            }
            DispatchQueue.main.async {
                for config in configs { self.config = config }
                for (sweep, config) in sweeps {
                    self.latestSweep = sweep
                    if self.useMaxHold {
                        self.maxHoldSweep = self.maxHoldSweep?.maxHold(with: sweep) ?? sweep
                    }
                }
                if let config = self.config ?? configs.last {
                    self.state = .connected(info: Self.infoString(config: config))
                } else if sweeps.isEmpty {
                    self.state = .connected(info: "RF Explorer — awaiting configuration")
                }
            }
        }
        // Ask the device to (re)send its configuration: `#` + len + `C0`.
        port.write(RFExplorerProtocol.frameCommand("C0"))
        if self.config == nil {
            // Keep the UI in `connecting` only briefly; sweeps may arrive
            // before the config reply on firmware that streams immediately.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, case .connecting = self.state else { return }
                self.state = .connected(info: "RF Explorer — no configuration reply")
            }
        }
    }

    func disconnect() {
        port.close()
        config = nil
        latestSweep = nil
        maxHoldSweep = nil
        state = .disconnected
    }

    func resetMaxHold() {
        maxHoldSweep = nil
    }

    /// Loads a sweep from an imported CSV trace (Chanalyzer export, RF
    /// Explorer CSV or any `frequency,dbm` table).
    func loadImport(_ sweep: SpectrumSweep) {
        latestSweep = sweep
        maxHoldSweep = sweep
        state = .connected(
            info: "\(sweep.source) — \(sweep.pointCount) points, "
                + String(format: "%.3f", sweep.startMHz) + "–"
                + String(format: "%.3f", sweep.endMHz) + " MHz"
        )
    }

    func clearImport() {
        latestSweep = nil
        maxHoldSweep = nil
        if !port.isOpen { state = .disconnected }
    }

    private static func infoString(config: RFExplorerProtocol.Config) -> String {
        String(
            format: "RF Explorer — %.3f–%.3f MHz, %d points, span %.2f MHz",
            config.startMHz,
            config.startMHz + config.stepMHz * Double(max(config.dataPoints - 1, 0)),
            config.dataPoints,
            config.stepMHz * Double(max(config.dataPoints - 1, 0))
        )
    }
}
