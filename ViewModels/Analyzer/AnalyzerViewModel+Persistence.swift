import Foundation
import Combine
import CoreWLAN
import LanFiCore
import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

extension AnalyzerViewModel {
    // MARK: - Persistence

    func toggleColumn(_ id: String) {
        if let idx = columnDefinitions.firstIndex(where: { $0.id == id }) {
            columnDefinitions[idx].isVisible.toggle()
            if !columnDefinitions[idx].isVisible {
                quickFilters.removeValue(forKey: id)
            }
            saveColumnSettings()
            // Принудительно уведомляем View об изменении
            objectWillChange.send()
        }
    }

    func saveColumnSettings() {
        if let data = try? JSONEncoder().encode(columnDefinitions) {
            UserDefaults.standard.set(data, forKey: AppSettingsKey.wifiColumns.rawValue)
        }
    }

    func loadColumnSettings() {
        if let data = UserDefaults.standard.data(forKey: AppSettingsKey.wifiColumns.rawValue),
            let saved = try? JSONDecoder().decode([ColumnDefinition].self, from: data)
        {
            columnDefinitions = normalizeColumnDefinitions(saved)
        }
    }

    func normalizeColumnDefinitions(_ saved: [ColumnDefinition]) -> [ColumnDefinition] {
        let sortedSaved = saved.sorted { $0.order < $1.order }
        var unique: [String: ColumnDefinition] = [:]
        for def in sortedSaved where unique[def.id] == nil {
            unique[def.id] = def
        }

        var normalized: [ColumnDefinition] = []
        var order = 0
        for def in ColumnDefinition.defaults {
            if var savedDef = unique[def.id] {
                savedDef.title = def.title
                if savedDef.width <= 0 { savedDef.width = def.width }
                savedDef.order = order
                normalized.append(savedDef)
            } else {
                var fallback = def
                fallback.order = order
                normalized.append(fallback)
            }
            order += 1
        }
        for def in sortedSaved where def.id.hasPrefix("expr:") && unique[def.id] != nil {
            var expression = def
            expression.order = order
            normalized.append(expression)
            order += 1
        }
        return normalized
    }

    func loadPreferences() {
        let defaults = UserDefaults.standard

        let savedInterval = defaults.double(forKey: refreshIntervalKey)
        if savedInterval >= 0.5 { refreshInterval = savedInterval }

        if defaults.object(forKey: AppSettingsKey.filterBand24.rawValue) != nil {
            filterBand24 = defaults.bool(forKey: AppSettingsKey.filterBand24.rawValue)
        }
        if defaults.object(forKey: AppSettingsKey.filterBand5.rawValue) != nil {
            filterBand5 = defaults.bool(forKey: AppSettingsKey.filterBand5.rawValue)
        }
        if defaults.object(forKey: AppSettingsKey.filterBand6.rawValue) != nil {
            filterBand6 = defaults.bool(forKey: AppSettingsKey.filterBand6.rawValue)
        }
        if defaults.object(forKey: AppSettingsKey.filterOther.rawValue) != nil {
            filterOther = defaults.bool(forKey: AppSettingsKey.filterOther.rawValue)
        }
        if defaults.object(forKey: AppSettingsKey.filterWiFi7.rawValue) != nil {
            filterWiFi7 = defaults.bool(forKey: AppSettingsKey.filterWiFi7.rawValue)
        }
        if defaults.object(forKey: AppSettingsKey.minSignal.rawValue) != nil {
            minSignalThreshold = defaults.double(forKey: AppSettingsKey.minSignal.rawValue)
        }
        if let rawRemove = defaults.object(forKey: AppSettingsKey.removeAfter.rawValue) as? Double,
            let interval = NetworkRemovalInterval(rawValue: rawRemove)
        {
            removeAfterInterval = interval
        }
        if let rawUnit = defaults.string(forKey: AppSettingsKey.signalUnit.rawValue),
            let mode = SignalDisplayMode(rawValue: rawUnit)
        {
            signalDisplayMode = mode
        }
        if defaults.object(forKey: AppSettingsKey.highlightConnected.rawValue) != nil {
            highlightConnectedNetworks = defaults.bool(forKey: AppSettingsKey.highlightConnected.rawValue)
        }
        if let sortKey = defaults.string(forKey: AppSettingsKey.sortKey.rawValue), ColumnId(rawValue: sortKey) != nil {
            currentSortKey = sortKey
        }
        if defaults.object(forKey: AppSettingsKey.sortAscending.rawValue) != nil {
            isSortAscending = defaults.bool(forKey: AppSettingsKey.sortAscending.rawValue)
        }
        if let rawGroup = defaults.string(forKey: AppSettingsKey.groupMode.rawValue),
            let mode = NetworkGroupMode(rawValue: rawGroup)
        {
            groupMode = mode
        }
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(refreshInterval, forKey: refreshIntervalKey)
        defaults.set(filterBand24, forKey: AppSettingsKey.filterBand24.rawValue)
        defaults.set(filterBand5, forKey: AppSettingsKey.filterBand5.rawValue)
        defaults.set(filterBand6, forKey: AppSettingsKey.filterBand6.rawValue)
        defaults.set(filterOther, forKey: AppSettingsKey.filterOther.rawValue)
        defaults.set(filterWiFi7, forKey: AppSettingsKey.filterWiFi7.rawValue)
        defaults.set(minSignalThreshold, forKey: AppSettingsKey.minSignal.rawValue)
        defaults.set(removeAfterInterval.rawValue, forKey: AppSettingsKey.removeAfter.rawValue)
        defaults.set(signalDisplayMode.rawValue, forKey: AppSettingsKey.signalUnit.rawValue)
        defaults.set(highlightConnectedNetworks, forKey: AppSettingsKey.highlightConnected.rawValue)
        if let currentSortKey {
            defaults.set(currentSortKey, forKey: AppSettingsKey.sortKey.rawValue)
        }
        defaults.set(isSortAscending, forKey: AppSettingsKey.sortAscending.rawValue)
        defaults.set(groupMode.rawValue, forKey: AppSettingsKey.groupMode.rawValue)
    }

    func maxHistoryPoints() -> Int {
        let interval = max(0.5, refreshInterval)
        let points = Int((historyWindowSeconds / interval).rounded())
        return max(20, min(300, points))
    }
}
