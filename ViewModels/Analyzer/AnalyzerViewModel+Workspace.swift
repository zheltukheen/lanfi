import Foundation
import Combine
import CoreWLAN
import LanFiCore
import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

extension AnalyzerViewModel {
    // MARK: - Public Methods

    func sort(by key: String, ascending: Bool) {
        currentSortKey = key
        isSortAscending = ascending
        // applyFilters вызовется автоматически через didSet
    }

    func formatSignal(_ dbm: Int) -> String {
        NetworkColumnFormatter.formatSignal(dbm, mode: signalDisplayMode)
    }

    func textForColumn(id: String, net: NetworkModel) -> String {
        if id.hasPrefix("expr:"),
            let uuid = UUID(uuidString: String(id.dropFirst(5))),
            let expression = expressionColumns.first(where: { $0.id == uuid })
        {
            return ExpressionEvaluator.evaluate(
                expression.template, network: net, metrics: analysis.metrics(for: net.id)
            )
        }
        if id.hasPrefix("field:") {
            let key = String(id.dropFirst("field:".count))
            return DecodedFieldCatalog.value(for: key, network: net) ?? "-"
        }
        guard let column = ColumnId(rawValue: id) else { return "-" }
        return columnFormatter.text(for: column, network: net)
    }

    /// G4: promotes one decoded field to a real table column. The id carries
    /// the stable key, so the column survives a reload and exports like any
    /// other column.
    func addDecodedFieldColumn(key: String, title: String) {
        let id = "field:\(key)"
        guard !columnDefinitions.contains(where: { $0.id == id }) else { return }
        let order = (columnDefinitions.map(\.order).max() ?? 0) + 1
        columnDefinitions.append(
            ColumnDefinition(
                id: id, title: title, width: 150, isVisible: true, order: order))
        saveColumnSettings()
        objectWillChange.send()
    }

    func hasDecodedFieldColumn(key: String) -> Bool {
        columnDefinitions.contains { $0.id == "field:\(key)" }
    }

    var columnFormatter: NetworkColumnFormatter {
        NetworkColumnFormatter(
            signalDisplayMode: signalDisplayMode,
            connectedBSSID: currentConnectedBSSID,
            metricsByNetworkId: analysis.metricsByNetworkId,
            annotationsByNetworkId: annotations
        )
    }

    func channelAdvice(for network: NetworkModel) -> ChannelAdvice? {
        ChannelAdvisor.advice(for: network, report: analysis, allNetworks: networks)
    }

    func metrics(for network: NetworkModel) -> NetworkMetrics? {
        analysis.metrics(for: network.id)
    }

    func annotation(for network: NetworkModel) -> NetworkAnnotation {
        annotationStore.annotation(for: network.id)
    }

    func applyBulkAnnotation(alias: String, notes: String, to ids: Set<String>) {
        for id in ids {
            var annotation = annotationStore.annotation(for: id)
            annotation.alias = alias
            annotation.notes = notes
            annotationStore.update(annotation, for: id)
        }
        annotations = annotationStore.annotations
    }

    func rowColor(for network: NetworkModel) -> NSColor? {
        if let custom = ColorHex.color(from: annotation(for: network).colorHex ?? "") {
            return custom
        }
        for rule in coloringRules where rule.isEnabled {
            let filterRule = NetworkFilterRule(field: rule.field, op: rule.op, value: rule.value)
            if NetworkFilterEngine.evaluate(
                filterRule, network: network,
                metrics: analysis.metrics(for: network.id),
                connectedBSSID: currentConnectedBSSID
            ), let color = ColorHex.color(from: rule.colorHex) {
                return color
            }
        }
        return nil
    }

    func setNetworkColor(_ hex: String, for network: NetworkModel) {
        var annotation = annotation(for: network)
        annotation.colorHex = hex
        updateAnnotation(annotation, for: network)
    }

    func addExpressionColumn(name: String, template: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        expressionColumns.append(ExpressionColumn(id: UUID(), name: trimmed, template: template))
        expressionColumnStore.save(expressionColumns)
        appendExpressionColumnDefinitions()
    }

    func updateExpressionColumn(_ column: ExpressionColumn) {
        guard let index = expressionColumns.firstIndex(where: { $0.id == column.id }) else { return }
        expressionColumns[index] = column
        expressionColumnStore.save(expressionColumns)
        appendExpressionColumnDefinitions()
    }

    func deleteExpressionColumn(_ column: ExpressionColumn) {
        expressionColumns.removeAll { $0.id == column.id }
        expressionColumnStore.save(expressionColumns)
        columnDefinitions.removeAll { $0.id == "expr:\(column.id.uuidString)" }
        saveColumnSettings()
        objectWillChange.send()
    }

    func appendExpressionColumnDefinitions() {
        columnDefinitions.removeAll { $0.id.hasPrefix("expr:") }
        var order = (columnDefinitions.map(\.order).max() ?? 0) + 1
        for expression in expressionColumns {
            columnDefinitions.append(
                ColumnDefinition(
                    id: "expr:\(expression.id.uuidString)",
                    title: expression.name,
                    width: 180,
                    isVisible: true,
                    order: order
                )
            )
            order += 1
        }
        saveColumnSettings()
    }

    func saveWorkspaceProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = WorkspaceProfile.new(
            name: trimmed,
            filter: currentFilterProfile(name: trimmed),
            columns: columnDefinitions,
            coloringRules: coloringRules,
            customFilters: customFilters,
            activeFilterId: activeFilterId
        )
        if let index = workspaceProfiles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            var updated = profile
            updated = WorkspaceProfile(
                id: workspaceProfiles[index].id, name: trimmed, filter: profile.filter,
                columns: profile.columns, coloringRules: profile.coloringRules,
                customFilters: profile.customFilters, activeFilterId: profile.activeFilterId,
                createdAt: workspaceProfiles[index].createdAt
            )
            workspaceProfiles[index] = updated
        } else {
            workspaceProfiles.append(profile)
        }
        workspaceProfileStore.save(workspaceProfiles)
    }

    func applyWorkspaceProfile(_ profile: WorkspaceProfile) {
        applyFilterProfile(profile.filter)
        columnDefinitions = normalizeColumnDefinitions(profile.columns)
        saveColumnSettings()
        coloringRules = profile.coloringRules
        coloringRuleStore.save(profile.coloringRules)
        customFilters = profile.customFilters
        customFilterStore.save(profile.customFilters)
        activeFilterId = profile.activeFilterId
        applyFilters()
        objectWillChange.send()
    }

    func deleteWorkspaceProfile(_ profile: WorkspaceProfile) {
        workspaceProfiles.removeAll { $0.id == profile.id }
        workspaceProfileStore.save(workspaceProfiles)
    }

    func promptSaveWorkspaceProfile() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.stringValue = "Workspace"
        let alert = NSAlert()
        alert.messageText = "Save workspace profile"
        alert.informativeText = "Save filters, bands, columns, coloring rules and custom filters."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            saveWorkspaceProfile(named: field.stringValue)
        }
    }

    func saveColoringRules(_ rules: [ColoringRule]) {
        coloringRules = rules
        coloringRuleStore.save(rules)
        objectWillChange.send()
    }

    func updateAnnotation(_ annotation: NetworkAnnotation, for network: NetworkModel) {
        annotationStore.update(annotation, for: network.id)
        annotations = annotationStore.annotations
        applyFilters()
    }

    var connectedNetwork: NetworkModel? {
        guard let bssid = currentConnectedBSSID else { return nil }
        return networks.first { $0.bssid == bssid }
    }

    func displayName(for network: NetworkModel) -> String {
        annotation(for: network).displayAlias ?? network.displaySSID
    }
}
