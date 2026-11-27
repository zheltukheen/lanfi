import Foundation
import Combine
import CoreWLAN
import LanFiCore
import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

extension AnalyzerViewModel {
    // MARK: - Sessions

    var isSessionMode: Bool { loadedSession != nil }

    @discardableResult
    func saveSession(named name: String) -> Bool {
        guard !persistentNetworks.isEmpty else {
            presentError("There are no scan results to save yet.")
            return false
        }
        do {
            let session = try sessionStore.save(
                name: name,
                networks: persistentNetworks.values.sorted { $0.displaySSID < $1.displaySSID },
                annotations: annotations
            )
            sessions = sessionStore.sessions()
            sessionMessage = "Saved session “\(session.displayName)”"
            return true
        } catch {
            presentError("Could not save the session: \(error.localizedDescription)")
            return false
        }
    }

    func loadSession(_ session: ScanSession) {
        timer?.invalidate()
        timer = nil
        loadedSession = session
        persistentNetworks = Dictionary(uniqueKeysWithValues: session.networks.map { ($0.id, $0) })
        annotations = session.annotations
        annotationStore.replaceAll(session.annotations)
        history = NetworkHistory()
        selectedNetworkId = nil
        analysis = NetworkAnalyzer.analyze(networks: session.networks)
        sessionMessage = "Session “\(session.displayName)” · \(session.networkCount) networks"
        applyFilters()
        refreshMenuBarAlerts()
    }

    func resumeLiveScan() {
        guard loadedSession != nil else { return }
        loadedSession = nil
        sessionMessage = nil
        persistentNetworks.removeAll()
        history = NetworkHistory()
        analysis = .empty
        applyFilters()
        startScanningLoop()
        refresh()
    }

    func deleteSession(_ session: ScanSession) {
        sessionStore.delete(session)
        sessions = sessionStore.sessions()
    }

    func promptSaveSession() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = "Scan \(Date().formatted(date: .abbreviated, time: .shortened))"
        let alert = NSAlert()
        alert.messageText = "Save scan session"
        alert.informativeText = "Sessions are stored locally and can be reopened without scanning."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = saveSession(named: field.stringValue)
        }
    }

    func promptOpenSession() {
        sessions = sessionStore.sessions()
        guard !sessions.isEmpty else {
            presentError("No saved sessions yet. Use Data → Save Session first.")
            return
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        for session in sessions {
            popup.addItem(withTitle: "\(session.displayName) · \(session.networkCount) networks")
        }
        let alert = NSAlert()
        alert.messageText = "Open scan session"
        alert.informativeText = "Live scanning pauses while a saved session is open."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let index = popup.indexOfSelectedItem
            guard sessions.indices.contains(index) else { return }
            loadSession(sessions[index])
        }
    }

    // 1. Вычисляемое свойство для выбранной сети (нужно для Инспектора)
    var selectedNetwork: NetworkModel? {
        guard let selectedNetworkId else { return nil }
        return networks.first { $0.id == selectedNetworkId }
    }

    var filterColumns: [FilterColumn] {
        columnDefinitions
            .sorted { $0.order < $1.order }
            .filter { $0.isVisible && $0.id != ColumnId.networkName.rawValue }
            .map { def in
                FilterColumn(
                    id: def.id,
                    title: def.displayTitle,
                    systemImage: filterIcon(for: def.id)
                )
            }
    }

    func filterIcon(for id: String) -> String {
        guard let column = ColumnId(rawValue: id) else { return "line.3.horizontal.decrease.circle" }
        switch column {
        case .band: return "antenna.radiowaves.left.and.right"
        case .channel: return "waveform.path.ecg"
        case .channelWidth: return "arrow.left.and.right"
        case .security: return "lock.shield"
        case .mode: return "dot.radiowaves.left.and.right"
        case .generation: return "sparkles"
        case .bssid, .apName: return "antenna.radiowaves.left.and.right"
        case .vendor: return "building.2"
        case .countryCode: return "globe"
        default: return "line.3.horizontal.decrease.circle"
        }
    }

    func sidebarOptions(for filter: FilterColumn) -> [(value: String, count: Int)] {
        let source = baseFilteredNetworks
        var counts: [String: Int] = [:]
        for net in source {
            counts[textForColumn(id: filter.id, net: net), default: 0] += 1
        }
        return counts.keys
            .sorted { lhs, rhs in
                let lc = counts[lhs, default: 0]
                let rc = counts[rhs, default: 0]
                if lc != rc { return lc > rc }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { (value: $0, count: counts[$0, default: 0]) }
    }

    func filterSelection(for filter: FilterColumn) -> Set<String> {
        quickFilters[filter.id] ?? []
    }

    func setFilterSelection(_ values: Set<String>, for filter: FilterColumn) {
        if values.isEmpty {
            quickFilters.removeValue(forKey: filter.id)
        } else {
            quickFilters[filter.id] = values
        }
        requestFilterUpdate()
    }

    var totalNetworkCount: Int { persistentNetworks.count }

    var hasActiveFilters: Bool {
        !searchText.isEmpty
            || !filterBand24 || !filterBand5 || !filterBand6 || !filterOther || !filterWiFi7
            || minSignalThreshold > -100
            || !quickFilters.isEmpty
            || activeFilterId != nil
    }

    func clearAllFilters() {
        searchText = ""
        filterBand24 = true
        filterBand5 = true
        filterBand6 = true
        filterOther = true
        filterWiFi7 = true
        minSignalThreshold = -100
        clearQuickFilters()
    }

    func clearQuickFilters() {
        quickFilters.removeAll()
        activeFilterId = nil
    }

    // 2. Методы управления столбцами (нужны для ColumnSettingsView)
    func resetColumnsToDefault() {
        columnDefinitions = ColumnDefinition.defaults
        saveColumnSettings()
    }

    func applyColumnProfile(_ profile: ColumnProfile) {
        columnDefinitions = normalizeColumnDefinitions(profile.columns)
        saveColumnSettings()
        objectWillChange.send()
    }

    func saveCurrentColumnsAsProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = columnProfiles.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            columnProfiles[index].columns = columnDefinitions
        } else {
            columnProfiles.append(.new(name: trimmed, columns: columnDefinitions))
        }
        columnProfileStore.save(columnProfiles)
    }

    func deleteColumnProfile(_ profile: ColumnProfile) {
        columnProfiles.removeAll { $0.id == profile.id }
        columnProfileStore.save(columnProfiles)
    }

    func promptSaveColumnProfile() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = "My layout"
        let alert = NSAlert()
        alert.messageText = "Save column profile"
        alert.informativeText = "Store the current column order, widths and visibility."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            saveCurrentColumnsAsProfile(named: field.stringValue)
        }
    }

    // 3. Публичные методы для геолокации (нужны для кнопок в UI)
    // Чтобы не обращаться к приватному locationManager из View
    /// Hides the identifier banner for the current session; the next scan with
    /// redacted identifiers brings it back.
    func dismissScanHealth() {
        scanHealth = .healthy
    }

    func requestLocationAuthorization() {
        access.request()
    }

    func openSystemLocationSettings() {
        access.openSystemSettings()
    }
}
