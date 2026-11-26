import Foundation

/// Builds the CSV export from a captured table snapshot, so encoding can run
/// away from the main actor.
struct ScanCSVExporter {
    let columns: [ColumnDefinition]
    let formatter: NetworkColumnFormatter
    let expressions: [ExpressionColumn]
    let metrics: [String: NetworkMetrics]

    func make(networks: [NetworkModel]) -> String {
        let visible = columns.sorted { $0.order < $1.order }.filter(\.isVisible)
        let headers = visible.map { "\"\($0.displayTitle)\"" }.joined(separator: ",")
        let rows = networks.map { network in
            visible.map { column in
                let value = text(columnID: column.id, network: network)
                return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ",")
        }
        return "\u{FEFF}" + ([headers] + rows).joined(separator: "\r\n") + "\r\n"
    }

    private func text(columnID: String, network: NetworkModel) -> String {
        if columnID.hasPrefix("expr:"),
            let uuid = UUID(uuidString: String(columnID.dropFirst(5))),
            let expression = expressions.first(where: { $0.id == uuid })
        {
            return ExpressionEvaluator.evaluate(
                expression.template, network: network, metrics: metrics[network.id])
        }
        if columnID.hasPrefix("field:") {
            let key = String(columnID.dropFirst("field:".count))
            return DecodedFieldCatalog.value(for: key, network: network) ?? "-"
        }
        guard let column = ColumnId(rawValue: columnID) else { return "-" }
        return formatter.text(for: column, network: network)
    }
}
