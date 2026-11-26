import Foundation
import Combine
import CoreWLAN
import LanFiCore
import AppKit
import PostHog
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

extension AnalyzerViewModel {
    // MARK: - Export (Improved CSV)

    func exportCSV() {
        exportCSV(networks: networks, suffix: "scan")
    }

    func exportCSV(networks: [NetworkModel], suffix: String) {
        let exporter = ScanCSVExporter(
            columns: columnDefinitions, formatter: columnFormatter,
            expressions: expressionColumns, metrics: analysis.metricsByNetworkId)
        presentSavePanel(
            defaultName: "LanFi-\(suffix)-\(Self.fileTimestamp()).csv",
            contentType: .commaSeparatedText,
            eventProperties: ["export_format": "csv", "network_count": networks.count],
            content: { exporter.make(networks: networks) }
        )
    }

    /// G4: one column per decoded field, header is the stable key, so nothing
    /// the decoder understood is lost between the table and the file.
    func exportDecodedFieldsCSV() {
        guard !networks.isEmpty else {
            presentError("There are no visible networks to export.")
            return
        }
        let exporter = DecodedFieldCSVExporter()
        let rows = networks
        presentSavePanel(
            defaultName: "LanFi-decoded-fields-\(Self.fileTimestamp()).csv",
            contentType: .commaSeparatedText,
            eventProperties: ["export_format": "decoded_fields_csv", "network_count": rows.count],
            content: { exporter.make(networks: rows) }
        )
    }

    func exportJSON() {
        exportJSON(networks: networks, suffix: "scan")
    }

    func exportJSON(networks: [NetworkModel], suffix: String) {
        let exporter = ScanJSONExporter(version: bundleVersion, analysis: analysis)
        presentSavePanel(
            defaultName: "LanFi-\(suffix)-\(Self.fileTimestamp()).json",
            contentType: .json,
            eventProperties: ["export_format": "json", "network_count": networks.count],
            content: {
                let payload = exporter.make(networks: networks)
                guard JSONSerialization.isValidJSONObject(payload) else {
                    throw ExportEncodingError.invalidJSON
                }
                let data = try JSONSerialization.data(
                    withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                guard let string = String(data: data, encoding: .utf8) else {
                    throw ExportEncodingError.invalidJSON
                }
                return string
            }
        )
    }

    private enum ExportEncodingError: Error {
        case invalidJSON
    }

    var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Shared shape for the JSON export and the MCP live snapshot.
    func scanJSONPayload(networks: [NetworkModel]) -> [String: Any] {
        ScanJSONExporter(version: bundleVersion, analysis: analysis).make(networks: networks)
    }

    /// Publishes the scan for the MCP server. Throttled because filters can
    /// recompute many times per second while the user types.
    func publishMCPSnapshotIfNeeded() {
        let defaults = UserDefaults.standard
        guard (defaults.object(forKey: AppSettingsKey.mcpPublishSnapshot.rawValue) as? Bool) ?? true else {
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastMCPSnapshotDate) >= 5 else { return }
        lastMCPSnapshotDate = now
        MCPSnapshotWriter.write(
            scanJSONPayload(networks: Array(persistentNetworks.values)))
    }

    func refreshMenuBarAlerts() {
        let defaults = UserDefaults.standard
        let weak = defaults.object(forKey: AppSettingsKey.alertsWeakSignal.rawValue) as? Bool ?? true
        let open = defaults.object(forKey: AppSettingsKey.alertsOpenNetwork.rawValue) as? Bool ?? true
        let channel = defaults.object(forKey: AppSettingsKey.alertsChannelChange.rawValue) as? Bool ?? true
        let previous = defaults.object(forKey: AppSettingsKey.alertsLastConnectedChannel.rawValue) as? Int
        menuBarAlerts = MenuBarAlertEngine.compute(
            networks: networks,
            connectedBSSID: currentConnectedBSSID,
            weakSignalEnabled: weak,
            openNetworkEnabled: open,
            channelChangeEnabled: channel,
            previousChannel: previous
        )
        if let connected = networks.first(where: { $0.bssid == currentConnectedBSSID }) {
            defaults.set(connected.channel, forKey: AppSettingsKey.alertsLastConnectedChannel.rawValue)
        }
    }

    var allFilters: [CustomFilter] {
        CustomFilter.automatic + customFilters
    }

    var activeFilter: CustomFilter? {
        guard let activeFilterId else { return nil }
        return allFilters.first { $0.id == activeFilterId }
    }

    func setActiveFilter(_ filter: CustomFilter?) {
        activeFilterId = filter?.id
        applyFilters()
    }

    func saveCustomFilter(_ filter: CustomFilter) {
        if let index = customFilters.firstIndex(where: { $0.id == filter.id }) {
            customFilters[index] = filter
        } else {
            customFilters.append(filter)
        }
        customFilterStore.save(customFilters)
        if activeFilterId == filter.id { applyFilters() }
    }

    func deleteCustomFilter(_ filter: CustomFilter) {
        customFilters.removeAll { $0.id == filter.id }
        if activeFilterId == filter.id { activeFilterId = nil }
        customFilterStore.save(customFilters)
        applyFilters()
    }

    /// Charts show everything for 0/1 selected networks, and only the selection
    /// when the user has deliberately selected two or more.
    var chartNetworks: [NetworkModel] {
        let selected =
            selectedNetworkIds.count >= 2
            ? networks.filter { selectedNetworkIds.contains($0.id) }
            : networks
        return selected.filter { network in
            switch network.band {
            case .band24: guard filterBand24 else { return false }
            case .band5: guard filterBand5 else { return false }
            case .band6: guard filterBand6 else { return false }
            case .unknown: guard filterOther else { return false }
            }
            if !filterWiFi7 && network.generation == .mode11be { return false }
            return true
        }
    }

    var selectedNetworks: [NetworkModel] {
        let ids = selectedNetworkIds
        if ids.isEmpty, let selectedNetwork {
            return [selectedNetwork]
        }
        return networks.filter { ids.contains($0.id) }
    }

    func setSelection(ids: Set<String>, primary: String?) {
        selectedNetworkIds = ids
        selectedNetworkIdStorage = primary ?? ids.first
    }

    func copySelectedNetworks() {
        let lines = selectedNetworks.map { "\($0.displaySSID) · \($0.bssid)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func exportSelectedCSV() {
        exportCSV(networks: selectedNetworks, suffix: "selection")
    }

    func exportSelectedJSON() {
        exportJSON(networks: selectedNetworks, suffix: "selection")
    }

    func currentFilterProfile(name: String = "LanFi filter") -> FilterProfile {
        FilterProfile.capture(
            name: name, searchText: searchText,
            band24: filterBand24, band5: filterBand5, band6: filterBand6,
            other: filterOther, wifi7: filterWiFi7,
            minSignal: minSignalThreshold, groupMode: groupMode,
            signalUnit: signalDisplayMode
        )
    }

    func applyFilterProfile(_ profile: FilterProfile) {
        searchText = profile.searchText
        filterBand24 = profile.band24
        filterBand5 = profile.band5
        filterBand6 = profile.band6
        filterOther = profile.other ?? true
        filterWiFi7 = profile.wifi7 ?? true
        minSignalThreshold = profile.minSignal
        if let mode = NetworkGroupMode(rawValue: profile.groupMode) {
            groupMode = mode
        }
        if let unit = SignalDisplayMode(rawValue: profile.signalUnit) {
            signalDisplayMode = unit
        }
    }

    func exportFilterProfile() {
        let panel = NSSavePanel()
        panel.title = "Export filter profile"
        panel.nameFieldStringValue = "LanFi-Filter.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(currentFilterProfile()) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func importExternalScan() {
        let panel = NSOpenPanel()
        panel.title = "Import scan"
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try GenericScanImporter.loadDetailed(url)
            let networks = result.networks
            guard !networks.isEmpty else {
                presentError("The import contained no usable networks.")
                return
            }
            presentUnmappedColumns(result.unmappedColumns)
            let session = ScanSession(
                id: UUID(), name: "Imported \(url.lastPathComponent)",
                createdAt: Date(), networks: networks, annotations: annotations
            )
            loadSession(session)
            PostHogSDK.shared.capture(
                "external_scan_imported",
                properties: ["import_source": "file", "network_count": networks.count])
        } catch {
            presentError("Import failed: \(error.localizedDescription)")
        }
    }

    func promptImportExternalScanURL() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 22))
        field.placeholderString = "https://example.com/scan.json"
        let alert = NSAlert()
        alert.messageText = "Import scan from URL"
        alert.informativeText = "Fetch a LanFi JSON export or a CSV scan from an HTTP(S) endpoint."
        alert.accessoryView = field
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme,
            scheme == "https" || scheme == "http"
        else {
            presentError("Enter a valid HTTP(S) URL.")
            return
        }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(
                        domain: "LanFi.Import", code: http.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"
                        ])
                }
                let result = try GenericScanImporter.loadDetailed(
                    data: data, filename: url.lastPathComponent.isEmpty ? "scan.json" : url.lastPathComponent
                )
                let networks = result.networks
                presentUnmappedColumns(result.unmappedColumns)
                guard !networks.isEmpty else {
                    presentError("The import contained no usable networks.")
                    return
                }
                loadSession(
                    ScanSession(
                        id: UUID(), name: "Imported \(url.host ?? "remote")",
                        createdAt: Date(), networks: networks, annotations: annotations
                    )
                )
                PostHogSDK.shared.capture(
                    "external_scan_imported",
                    properties: ["import_source": "url", "network_count": networks.count])
            } catch {
                presentError("Import failed: \(error.localizedDescription)")
            }
        }
    }

    func importFilterProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import filter profile"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url),
            let profile = try? JSONDecoder().decode(FilterProfile.self, from: data)
        else {
            presentError("Could not decode the filter profile.")
            return
        }
        applyFilterProfile(profile)
    }

    func exportPCAP() {
        guard !networks.isEmpty else {
            presentError("There are no visible networks to export.")
            return
        }
        let data = PcapExporter.makeCapture(networks: networks)
        presentSaveData(
            defaultName: "LanFi-Scan-\(Self.fileTimestamp()).pcap",
            contentType: UTType(filenameExtension: "pcap") ?? .data,
            data: data
        )
    }

    func exportPCAPNG() {
        guard !networks.isEmpty else {
            presentError("There are no visible networks to export.")
            return
        }
        let data = PcapExporter.makePcapngCapture(networks: networks)
        presentSaveData(
            defaultName: "LanFi-Scan-\(Self.fileTimestamp()).pcapng",
            contentType: UTType(filenameExtension: "pcapng") ?? .data,
            data: data
        )
    }

    func presentSaveData(defaultName: String, contentType: UTType, data: Data) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            Task.detached(priority: .utility) {
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    let message = "Could not save the capture: \(error.localizedDescription)"
                    await MainActor.run {
                        self?.presentError(message)
                    }
                }
            }
        }
    }

    func presentSavePanel(
        defaultName: String, contentType: UTType, eventProperties: [String: Any],
        content: @escaping () throws -> String
    ) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            Task.detached(priority: .utility) {
                let exportFormat = eventProperties["export_format"] as? String ?? "unknown"
                let networkCount = eventProperties["network_count"] as? Int ?? 0
                do {
                    let text = try content()
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    PostHogSDK.shared.capture("scan_exported", properties: eventProperties)
                    PostHogSDK.shared.logger?.info(
                        "scan export completed",
                        attributes: ["export_format": exportFormat, "network_count": networkCount])
                } catch {
                    PostHogSDK.shared.logger?.error(
                        "scan export failed", attributes: ["export_format": exportFormat])
                    let message = "Could not save the file: \(error.localizedDescription)"
                    await MainActor.run {
                        self?.presentError(message)
                    }
                }
            }
        }
    }

    /// G4b: imported files often carry columns LanFi has no use for. Naming
    /// them is better than a silent drop that looks like data loss.
    func presentUnmappedColumns(_ columns: [String]) {
        guard !columns.isEmpty else { return }
        let notice = NSAlert()
        notice.alertStyle = .informational
        notice.messageText = "Some columns were not imported"
        notice.informativeText =
            "No LanFi field matched: \(columns.prefix(12).joined(separator: ", "))"
            + (columns.count > 12 ? " and \(columns.count - 12) more." : ".")
        notice.runModal()
    }

    func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export failed"
        alert.informativeText = message
        alert.runModal()
    }

    static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
