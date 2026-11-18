import Foundation
import Combine
import CoreWLAN
import LanFiCore
import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

extension AnalyzerViewModel {
    // MARK: - Scanning Loop

    func startScanningLoop() {
        timer?.invalidate()
        let interval = currentScanInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isAutoScanPaused else { return }
                self.refresh()
            }
        }
        timer?.tolerance = max(0.2, interval * 0.1)
    }

    /// Rebuilds the timer after an activity, power or preference change.
    func refreshScanCadence() {
        guard loadedSession == nil else { return }
        startScanningLoop()
    }

    var currentScanInterval: TimeInterval {
        let reduce = UserDefaults.standard.object(forKey: Self.backgroundScanKey) as? Bool ?? true
        return ScanCadence(
            baseInterval: refreshInterval, reduceInBackground: reduce,
            lowPowerMode: isLowPowerMode
        ).interval(isForeground: isAppActive)
    }

    func updateRefreshInterval(to newValue: Double) {
        refreshInterval = newValue
        UserDefaults.standard.set(newValue, forKey: refreshIntervalKey)
        var settings = AppSettingsStore.shared.settings
        settings.refreshInterval = newValue
        AppSettingsStore.shared.save(settings)
        if loadedSession == nil {
            startScanningLoop()
        }
    }

    #if DEBUG
        /// Snapshot harness only: fills the table with deterministic fixtures so
        /// screenshots do not depend on Location access or the current radio.
        func seedDemoData() {
            isDemoSeeded = true
            timer?.invalidate()
            timer = nil
            loadedSession = nil
            isAutoScanPaused = true
            isLocationAuthorized = true
            let demo = DemoData.networks()
            persistentNetworks = Dictionary(uniqueKeysWithValues: demo.map { ($0.id, $0) })
            let connected = demo.first {
                $0.ssid == "LanFi-Office" && $0.band == .band5
            }
            currentConnectedBSSID = connected?.bssid
            selectedNetworkId = connected?.id
            lastScanDate = Date()
            scanHealth = .healthy
            history = NetworkHistory()
            analysis = NetworkAnalyzer.analyze(networks: demo)
            applyFilters()
        }
    #endif

    // MARK: - Scan modes

    /// Switches how the analyzer collects networks. Passive and directed runs
    /// are on demand, so the automatic timer pauses while they are selected and
    /// resumes with active mode.
    func selectScanMode(_ mode: ScanMode) {
        guard loadedSession == nil else { return }
        passiveScan.selectMode(mode)
        isAutoScanPaused = mode != .active
        if mode == .active {
            startScanningLoop()
            refresh()
        }
    }

    /// Merges a passive/directed capture into the same persistent list, so
    /// history, annotations and analysis keep working.
    func ingestPassiveNetworks(_ networks: [NetworkModel]) {
        guard !networks.isEmpty else { return }
        errorMessage = nil
        lastScanDate = Date()
        scanHealth = ScanHealthEvaluator.evaluate(
            networks: networks, errorMessage: nil,
            isLocationAuthorized: isLocationAuthorized)
        mergeNetworks(networks)
    }

    // MARK: - Refresh Logic (Async/Await)

    func refresh() {
        #if DEBUG
            guard !isDemoSeeded else { return }
        #endif
        guard !isScanning, loadedSession == nil else { return }
        supportedChannels = SpectrumCapabilities.current()
        isScanning = true

        let currentBSSID = CWWiFiClient.shared().interface()?.bssid()?.uppercased()

        // Используем Task для вызова метода Actor-а
        Task {
            defer { isScanning = false }

            do {
                // Асинхронный вызов к WiFiScanner (не блокирует Main Thread)
                let scannedList = try await scanner.scan()

                // Следующий код выполняется автоматически на MainActor, т.к. класс помечен им
                self.errorMessage = nil
                self.currentConnectedBSSID = currentBSSID
                self.lastScanDate = Date()
                self.scanHealth = ScanHealthEvaluator.evaluate(
                    networks: scannedList, errorMessage: nil,
                    isLocationAuthorized: self.isLocationAuthorized)
                self.mergeNetworks(scannedList)

            } catch let error as WiFiError {
                // Обработка типизированных ошибок
                if case .interfaceNotFound = error {
                    self.errorMessage = nil
                    self.scanHealth = .noWiFiHardware
                } else if case .wifiPoweredOff = error {
                    self.errorMessage = "Wi-Fi is off"
                    self.scanHealth = .scanFailed("Wi-Fi is off")
                } else {
                    self.errorMessage = error.localizedDescription
                    self.scanHealth = .scanFailed(error.localizedDescription)
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.scanHealth = .scanFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Data Processing

    func mergeNetworks(_ newScan: [NetworkModel]) {
        let now = Date()
        let maxPoints = maxHistoryPoints()
        var updatedHistory = history

        // 1. Update Existing
        for net in newScan {
            let existing = persistentNetworks[net.id]
            let updated = observing(net: net, existing: existing, now: now)
            persistentNetworks[net.id] = updated
            updatedHistory.record(updated, maxPoints: maxPoints)
        }

        // 2. Cleanup Old
        let threshold = now.addingTimeInterval(-removeAfterInterval.rawValue)
        let keysToRemove = persistentNetworks.filter { $0.value.lastSeen ?? Date.distantPast < threshold }.map {
            $0.key
        }

        for key in keysToRemove {
            persistentNetworks.removeValue(forKey: key)
            updatedHistory.remove(key)
        }

        // Publish the whole history once per scan instead of once per network.
        history = updatedHistory

        let visible = Array(persistentNetworks.values)
        if let bssid = currentConnectedBSSID {
            // A scan can occasionally omit the connected BSSID. Keep the last
            // monitor state instead of recording a false disconnect.
            if let connected = visible.first(where: { $0.bssid == bssid }) {
                monitor.ingest(connected: connected, visible: visible)
            }
        } else {
            monitor.ingest(connected: nil, visible: visible)
        }

        analysis = NetworkAnalyzer.analyze(networks: Array(persistentNetworks.values))
        applyFilters()
        refreshMenuBarAlerts()
    }

    func observing(net: NetworkModel, existing: NetworkModel?, now: Date) -> NetworkModel {
        let firstSeen = existing?.firstSeen ?? now
        let count = (existing?.count ?? 0) + 1

        return NetworkModel(
            id: net.id,
            bssid: net.bssid,
            ssid: net.ssid,
            band: net.band,
            channel: net.channel,
            channelWidthMHz: net.channelWidthMHz,
            generation: net.generation,
            security: net.security,
            vendor: net.vendor,
            apName: net.apName,
            mode: net.mode,
            signal: net.signal,
            noise: net.noise,
            snr: net.snr,
            basicRates: net.basicRates,
            minBasicRate: net.minBasicRate,
            maxBasicRate: net.maxBasicRate,
            minRate: net.minRate,
            maxRate: net.maxRate,
            centerFrequency: net.centerFrequency,
            channelUtilization: net.channelUtilization,
            beaconInterval: net.beaconInterval,
            beaconRate: net.beaconRate,
            beaconAirtime: net.beaconAirtime,
            beaconMode: net.beaconMode,
            countryCode: net.countryCode,
            fastTransition: net.fastTransition,
            protectionMode: net.protectionMode,
            stations: net.stations,
            clients: net.clients,
            streams: net.streams,
            type: net.type,
            wps: net.wps,
            wpsEnabled: net.wpsEnabled,
            pmfRequired: net.pmfRequired,
            ieCount: net.ieCount,
            ieTotalLength: net.ieTotalLength,
            ratesEstimated: net.ratesEstimated,
            informationElements: net.informationElements,
            count: count,
            firstSeen: firstSeen,
            lastSeen: now
        )
    }
}
