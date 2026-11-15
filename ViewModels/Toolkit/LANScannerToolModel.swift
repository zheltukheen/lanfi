import Foundation
import SwiftUI

// MARK: - LAN scanner

@MainActor
final class LANScannerToolModel: ObservableObject {
    @Published private(set) var result: LANScanResult?
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    @Published private(set) var newMACs: Set<String> = []
    @Published var guardEnabled: Bool {
        didSet {
            defaults.set(guardEnabled, forKey: Self.guardKey)
            if guardEnabled, let result {
                knownMACs.formUnion(result.devices.map { $0.mac ?? $0.ip })
                guardStore.save(knownMACs)
            } else if !guardEnabled {
                newMACs = []
            }
        }
    }

    private static let guardKey = "LanFi.lanGuardEnabled"
    private let defaults = UserDefaults.standard
    private let guardStore = LANGuardStore()
    private let notifier: any UserNotifying
    private var knownMACs: Set<String>
    private var task: Task<Void, Never>?

    init(notifier: any UserNotifying = SystemUserNotifier()) {
        self.notifier = notifier
        knownMACs = guardStore.load()
        guardEnabled = defaults.bool(forKey: Self.guardKey)
    }

    var devices: [LANDevice] { result?.devices ?? [] }

    var selectedSubnet: String { result?.subnet ?? String(localized: "Not scanned") }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let known = knownMACs
        let guarding = guardEnabled
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let scan = try await LANScannerService().scan(
                    knownMACs: known, guardEnabled: guarding)
                if Task.isCancelled { return }
                self.result = scan
                self.applyGuard(scan)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isScanning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    func clear() {
        stop()
        result = nil
        newMACs = []
        errorMessage = nil
    }

    private func applyGuard(_ scan: LANScanResult) {
        guard guardEnabled else { return }
        let seen = Set(scan.devices.map { $0.mac ?? $0.ip })
        if knownMACs.isEmpty {
            knownMACs = seen
            guardStore.save(knownMACs)
            return
        }
        let new = seen.subtracting(knownMACs)
        newMACs = new
        if !new.isEmpty {
            let names = scan.devices
                .filter { device in new.contains(device.mac ?? device.ip) }
                .map(\.displayName)
                .prefix(3)
                .joined(separator: ", ")
            Task {
                await notifier.notify(
                    title: "New device on \(scan.subnet)", body: names)
            }
        }
        knownMACs.formUnion(seen)
        guardStore.save(knownMACs)
    }
}
