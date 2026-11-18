import LanFiCore
import Foundation
import SwiftUI

// MARK: - iperf3

@MainActor
final class Iperf3ToolModel: ObservableObject {
    @Published var host = "192.168.1.10"
    @Published var portText = "5201"
    @Published var duration = 10
    @Published var direction: Iperf3Direction = .upload
    @Published private(set) var report: Iperf3Report?
    @Published private(set) var isRunning = false
    @Published private(set) var savedServers: [Iperf3Server] = []
    @Published private(set) var history: [Iperf3Measurement] = []
    @Published private(set) var executable: String? = Iperf3Runner.locate()
    @Published private(set) var isInstalling = false
    @Published private(set) var installSucceeded: Bool?
    @Published private(set) var installOutput: String?
    @Published var errorMessage: String?

    private let historyStore = Iperf3HistoryStore()
    private let serversKey = AppSettingsKey.iperf3Servers.rawValue
    private var task: Task<Void, Never>?

    var isInstalled: Bool { executable != nil }
    var newestFirst: [Iperf3Measurement] { Array(history.reversed()) }

    init() {
        history = (try? historyStore.load()) ?? []
        if let data = UserDefaults.standard.data(forKey: serversKey),
            let servers = try? JSONDecoder().decode([Iperf3Server].self, from: data)
        {
            savedServers = servers
        }
    }

    func saveCurrentServer() {
        guard let parsed = ToolTarget.parse(host), let port = UInt16(portText), port > 0
        else { return }
        savedServers.removeAll { $0.host == parsed.host && $0.port == port }
        savedServers.insert(
            Iperf3Server(name: parsed.host, host: parsed.host, port: port), at: 0)
        if savedServers.count > 12 { savedServers.removeLast(savedServers.count - 12) }
        persistServers()
    }

    func applyServer(_ server: Iperf3Server) {
        host = server.host
        portText = String(server.port)
    }

    func removeServer(_ server: Iperf3Server) {
        savedServers.removeAll { $0.id == server.id }
        persistServers()
    }

    func clearHistory() {
        history = []
        historyStore.clear()
    }

    /// Installs the Homebrew formula and refreshes `isInstalled`, so the Run
    /// button becomes available without relaunching the app.
    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        installSucceeded = nil
        installOutput = nil
        Task { [weak self] in
            guard let self else { return }
            let result = await ToolInstaller.install(package: "iperf3")
            self.executable = Iperf3Runner.locate()
            self.isInstalling = false
            self.installSucceeded = result.succeeded && self.executable != nil
            self.installOutput = result.message
            if self.isInstalled { self.errorMessage = nil }
        }
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(savedServers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
    }

    private func record(_ report: Iperf3Report) {
        history.append(Iperf3Measurement(report: report))
        if history.count > 50 { history.removeFirst(history.count - 50) }
        try? historyStore.save(history)
    }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host), let port = UInt16(portText), port > 0 else {
            errorMessage = "Enter a host and a port between 1 and 65535."
            return
        }
        errorMessage = nil
        report = nil
        isRunning = true
        let duration = duration
        let direction = direction
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let measured = try await Iperf3Runner().run(
                    host: target.host,
                    port: port,
                    durationSeconds: duration,
                    direction: direction
                )
                if Task.isCancelled { return }
                self.report = measured
                self.record(measured)
            } catch is CancellationError {
                // Keep whatever the user already has.
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        report = nil
        errorMessage = nil
    }
}
