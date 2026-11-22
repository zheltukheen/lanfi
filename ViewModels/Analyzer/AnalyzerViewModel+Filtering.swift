import Foundation
import Combine
import CoreWLAN
import LanFiCore
import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

extension AnalyzerViewModel {
    // MARK: - Filtering & Sorting

    func configureScheduledReports() {
        scheduledReportTimer?.invalidate()
        scheduledReportTimer = nil
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettingsKey.reportsEnabled.rawValue),
            let folder = defaults.string(forKey: AppSettingsKey.reportsFolder.rawValue),
            !folder.isEmpty
        else { return }
        let minutes = max(defaults.integer(forKey: AppSettingsKey.reportsMinutes.rawValue), 5)
        scheduledReportTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.writeScheduledReport() }
        }
    }

    func writeScheduledReport() {
        let defaults = UserDefaults.standard
        guard let folder = defaults.string(forKey: AppSettingsKey.reportsFolder.rawValue), !folder.isEmpty else {
            return
        }
        let format = defaults.string(forKey: AppSettingsKey.reportsFormat.rawValue) ?? "CSV"
        let ext: String
        switch format {
        case "PDF": ext = "pdf"
        case "Combined HTML": ext = "html"
        default: ext = "csv"
        }
        let url = URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent("LanFi-Report-\(Self.fileTimestamp()).\(ext)")
        if format == "Combined HTML" {
            let report = CombinedReportBuilder.make(
                networks: networks,
                analysis: analysis,
                survey: SurveyStore().latestProject(),
                diagnostics: nil,
                speedTests: ThroughputHistoryStore().load(),
                events: monitor.events
            )
            try? CombinedReportExporter.html(for: report)
                .write(to: url, atomically: true, encoding: .utf8)
        } else if format == "PDF" {
            let data = ScanReportExporter.makePDF(
                title: "LanFi scan report", networks: networks, columns: columnDefinitions
            ) { [weak self] id, network in
                self?.textForColumn(id: id, net: network) ?? ""
            }
            try? data.write(to: url, options: .atomic)
        } else {
            let exporter = ScanCSVExporter(
                columns: columnDefinitions, formatter: columnFormatter,
                expressions: expressionColumns, metrics: analysis.metricsByNetworkId)
            try? exporter.make(networks: networks).write(to: url, atomically: true, encoding: .utf8)
        }
        sessionMessage = "Scheduled report saved: \(url.lastPathComponent)"
    }

    func requestFilterUpdate() {
        // Простой debounce не нужен здесь, так как toggles нажимаются редко.
        // Выполняем сразу.
        applyFilters()
    }

    func applyFilters() {
        let allItems = Array(persistentNetworks.values)
        let query = searchText.lowercased()

        // 1. Filter
        var baseFiltered = allItems.filter { net in
            if !filterBand24 && net.band == .band24 { return false }
            if !filterBand5 && net.band == .band5 { return false }
            if !filterBand6 && net.band == .band6 { return false }
            if !filterOther && net.band == .unknown { return false }
            if !filterWiFi7 && net.generation == .mode11be { return false }
            if Double(net.signal) < minSignalThreshold { return false }

            if !query.isEmpty {
                let matches =
                    net.ssid.lowercased().contains(query) || net.bssid.lowercased().contains(query)
                    || net.vendor.lowercased().contains(query)
                if !matches { return false }
            }
            return true
        }

        baseFilteredNetworks = baseFiltered

        // 2. Quick Filters (Sidebar)
        for (columnID, values) in quickFilters where !values.isEmpty {
            guard columnDefinitions.first(where: { $0.id == columnID })?.isVisible == true else { continue }
            baseFiltered = baseFiltered.filter { values.contains(textForColumn(id: columnID, net: $0)) }
        }
        if let activeFilter {
            baseFiltered = baseFiltered.filter {
                activeFilter.matches(
                    $0,
                    metrics: analysis.metrics(for: $0.id),
                    connectedBSSID: currentConnectedBSSID
                )
            }
        }

        var filtered = baseFiltered

        // 3. Sort
        if let keyString = currentSortKey, let key = ColumnId(rawValue: keyString) {
            filtered.sort { p1, p2 in
                let formatter = columnFormatter
                let forward = formatter.compare(p1, p2, by: key)
                let backward = formatter.compare(p2, p1, by: key)
                if !forward && !backward { return p1.id < p2.id }
                return isSortAscending ? forward : backward
            }
        }

        self.networks = filtered
        self.tableRows = NetworkGrouper.rows(
            for: filtered,
            mode: groupMode,
            metricsByNetworkId: analysis.metricsByNetworkId,
            annotationsByNetworkId: annotations
        )
        if let selectedId = selectedNetworkId, !filtered.contains(where: { $0.id == selectedId }) {
            selectedNetworkId = nil
        }
        publishMCPSnapshotIfNeeded()
    }
}
