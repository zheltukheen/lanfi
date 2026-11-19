import AppKit
import Foundation
import LanFiCore

/// P3.8 — watches physical Ethernet links and, when the user has opted in,
/// turns Wi-Fi off while a cable is up and back on when it goes away.
///
/// The first-run toggle explains the write action; the feature is off by
/// default and has a master pause. Every check is a local `networksetup` read
/// or write, nothing leaves the Mac.
@MainActor
final class LinkAutomation: ObservableObject {
    static let shared = LinkAutomation()
    static let pollInterval: TimeInterval = 10

    @Published private(set) var wiredInterface: String?
    @Published private(set) var wifiDevice: String?
    @Published private(set) var wifiPowerOn: Bool?
    @Published private(set) var lastAction: LinkAutomationAction?
    @Published private(set) var lastActionAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSampling = false
    @Published var isPaused = false {
        didSet { policy.isPaused = isPaused }
    }

    private var policy = LinkAutomationPolicy()
    private var timer: Timer?
    private var ports: [HardwarePort] = []
    private var isSampleInFlight = false
    private var wakeObserver: NSObjectProtocol?

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    var isEnabled: Bool {
        AppSettingsStore.shared.settings.automation.linkAutomation
    }

    var wiredConnected: Bool { wiredInterface != nil }

    func start() {
        guard timer == nil else { return }
        policy.isPaused = isPaused
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        timer.tolerance = Self.pollInterval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample(afterWake: true) }
        }
        Task { await sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func sampleNow() async {
        await sample()
    }

    // MARK: - Sampling

    private func sample(afterWake: Bool = false) async {
        guard !isSampleInFlight else { return }
        isSampleInFlight = true
        isSampling = true
        defer {
            isSampling = false
            isSampleInFlight = false
        }

        if ports.isEmpty {
            ports = HardwarePortsOutput.parse(
                await Self.run("/usr/sbin/networksetup", ["-listallhardwareports"]))
        }
        wifiDevice = LinkAutomationClassifier.wifiPort(ports)?.device

        var active: String?
        for port in LinkAutomationClassifier.ethernetPorts(ports) {
            let output = await Self.run("/sbin/ifconfig", [port.device])
            if IfconfigOutput.isActive(output) {
                active = port.device
                break
            }
        }
        wiredInterface = active

        if let wifiDevice, !wifiDevice.isEmpty {
            let power = await Self.run("/usr/sbin/networksetup", ["-getairportpower", wifiDevice])
            wifiPowerOn = AirportPowerOutput.isOn(power)
        }

        policy.isEnabled = isEnabled
        policy.isPaused = isPaused

        let wifiOn = wifiPowerOn ?? true
        let action: LinkAutomationAction?
        if afterWake {
            action = policy.reapplyAfterWake(
                wiredConnected: active != nil, wifiOn: wifiOn)
        } else {
            action = policy.evaluate(wiredConnected: active != nil, wifiOn: wifiOn)
        }
        guard let action else { return }
        await perform(action)
    }

    private func perform(_ action: LinkAutomationAction) async {
        guard let wifiDevice, !wifiDevice.isEmpty else { return }
        let argument = action == .disableWiFi ? "off" : "on"
        lastError = nil
        let result = await Self.runWithStatus(
            "/usr/sbin/networksetup", ["-setairportpower", wifiDevice, argument])
        if result.status != 0 {
            lastError =
                result.output.isEmpty
                ? String(localized: "macOS refused to change Wi-Fi power.")
                : result.output
            return
        }
        lastAction = action
        lastActionAt = Date()
        let power = await Self.run("/usr/sbin/networksetup", ["-getairportpower", wifiDevice])
        wifiPowerOn = AirportPowerOutput.isOn(power)
        MonitorNotifier.shared.post(
            title: action == .disableWiFi
                ? String(localized: "Wi-Fi turned off") : String(localized: "Wi-Fi restored"),
            body: action.detail, identifier: "lanfi.link-automation")
    }

    // MARK: - Commands

    private static func run(_ path: String, _ arguments: [String]) async -> String {
        await runWithStatus(path, arguments).output
    }

    private static func runWithStatus(
        _ path: String, _ arguments: [String]
    ) async -> (output: String, status: Int32) {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return ("", -1) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus)
        }.value
    }
}
