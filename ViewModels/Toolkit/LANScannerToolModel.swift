import LanFiCore
import Foundation
import SwiftUI

// MARK: - LAN scanner

@MainActor
final class LANScannerToolModel: ObservableObject {
    @Published private(set) var result: LANScanResult?
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    @Published private(set) var newMACs: Set<String> = []
    /// Every device seen before, with its authorization flag. Empty until the
    /// first guarded scan seeds it.
    @Published private(set) var inventory: DeviceInventoryState
    /// The last switch read, kept so the device inspector can show where a MAC
    /// was learned after the lookup sheet closes.
    @Published private(set) var switchInventory: SwitchInventory?
    @Published private(set) var switchHost: String?
    @Published var guardEnabled: Bool {
        didSet {
            defaults.set(guardEnabled, forKey: Self.guardKey)
            if guardEnabled, let result {
                // Adopt what is on screen now so switching the guard on does
                // not announce the whole network as new.
                absorb(result)
            } else if !guardEnabled {
                newMACs = []
            }
        }
    }

    private static let guardKey = AppSettingsKey.lanGuardEnabled.rawValue
    private let defaults = UserDefaults.standard
    private let guardStore = LANGuardStore()
    private let notifier: any UserNotifying
    private var task: Task<Void, Never>?

    init(notifier: any UserNotifying = SystemUserNotifier()) {
        self.notifier = notifier
        inventory = guardStore.loadState()
        guardEnabled = defaults.bool(forKey: Self.guardKey)
    }

    var devices: [LANDevice] { result?.devices ?? [] }

    var selectedSubnet: String { result?.subnet ?? String(localized: "Not scanned") }

    var authorizedKeys: Set<String> { inventory.authorizedKeys }

    /// Devices on screen that the user has not confirmed as belonging here.
    var unverifiedDevices: [LANDevice] {
        devices.filter { !isAuthorized($0) }
    }

    /// Known devices that this scan did not return.
    var missingDevices: [DeviceInventoryEntry] {
        let seen = Set(devices.map(deviceKey))
        return inventory.entries.values
            .filter { !seen.contains($0.key) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let known = Set(inventory.entries.keys)
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

    // MARK: - Inventory

    func deviceKey(_ device: LANDevice) -> String { device.mac ?? device.ip }

    func isAuthorized(_ device: LANDevice) -> Bool {
        inventory.authorizedKeys.contains(deviceKey(device))
    }

    func authorize(_ device: LANDevice) {
        let key = deviceKey(device)
        var state = inventory
        state.authorize([key])
        inventory = state
        guardStore.save(state)
        newMACs.remove(key)
    }

    func authorizeAll() {
        var state = inventory
        state.authorizeAll()
        inventory = state
        guardStore.save(state)
        newMACs = []
    }

    private func absorb(_ scan: LANScanResult) {
        let change = DeviceInventoryEvaluator.evaluate(
            state: inventory, observed: records(scan))
        inventory = change.state
        guardStore.save(change.state)
    }

    private func applyGuard(_ scan: LANScanResult) {
        guard guardEnabled else { return }
        let change = DeviceInventoryEvaluator.evaluate(
            state: inventory, observed: records(scan))
        inventory = change.state
        guardStore.save(change.state)
        newMACs = Set(change.added.map(\.key))
        guard !change.added.isEmpty else { return }
        let names = change.added.map(\.name).prefix(3).joined(separator: ", ")
        Task {
            await notifier.notify(
                title: "New device on \(scan.subnet)", body: names)
        }
    }

    private func records(_ scan: LANScanResult) -> [LANDeviceRecord] {
        scan.devices.map { LANDeviceRecord(key: deviceKey($0), name: $0.displayName) }
    }

    // MARK: - Switch

    func applySwitchInventory(_ inventory: SwitchInventory, host: String) {
        switchInventory = inventory
        switchHost = host
    }

    func clearSwitchInventory() {
        switchInventory = nil
        switchHost = nil
    }

    func switchPort(for device: LANDevice) -> SwitchPortEntry? {
        guard let mac = device.mac else { return nil }
        return switchInventory?.bridge.port(forMAC: mac)
    }
}
