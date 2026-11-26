import SwiftUI

/// G4: every decoded value that is not already a column, searchable, with a
/// one-click promotion to a real table column.
struct FieldCatalogView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    @State private var query = ""
    @State private var selectedNetworkID: String?

    private var network: NetworkModel? {
        viewModel.networks.first { $0.id == selectedNetworkID }
            ?? viewModel.networks.max { $0.signal < $1.signal }
    }

    private var allFields: [DecodedField] {
        guard let network else { return [] }
        return DecodedFieldCatalog.fields(for: network)
    }

    private var filteredFields: [DecodedField] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allFields }
        return allFields.filter { field in
            field.key.localizedCaseInsensitiveContains(trimmed)
                || field.label.localizedCaseInsensitiveContains(trimmed)
                || field.value.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.networks.isEmpty {
                emptyState
            } else {
                fieldList
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            if selectedNetworkID == nil {
                selectedNetworkID = viewModel.networks.max { $0.signal < $1.signal }?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Decoded fields")
                .font(.title3.bold())
            Text(
                "Values LanFi decoded from the beacon but does not show in the table. Search one and add it as a column; the column id is the stable field key."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            HStack(spacing: 10) {
                Picker("Network", selection: $selectedNetworkID) {
                    ForEach(viewModel.networks.sorted { $0.signal > $1.signal }) { network in
                        Text("\(network.displaySSID) · \(network.bssid)")
                            .tag(Optional(network.id))
                    }
                }
                .frame(maxWidth: 320)
                TextField("Filter fields", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
                Text("\(filteredFields.count) of \(allFields.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(DesignToken.Spacing.card)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No networks in this scan")
                .font(.headline)
            Text("Run a scan, then open the catalogue again.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fieldList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(DecodedFieldGroup.allCases) { group in
                    let fields = filteredFields.filter { $0.group == group }
                    if !fields.isEmpty {
                        Text(group.title.uppercased())
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, DesignToken.Spacing.card)
                            .padding(.top, DesignToken.Spacing.small)
                            .padding(.bottom, 2)
                        ForEach(fields) { field in
                            row(field)
                        }
                        Divider()
                    }
                }
                if filteredFields.isEmpty {
                    Text("No field matches “\(query)”.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(DesignToken.Spacing.card)
                }
            }
        }
    }

    private func row(_ field: DecodedField) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(field.label)
                    .font(.caption.weight(.medium))
                Text(field.key)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            .frame(width: 230, alignment: .leading)
            Text(field.value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(viewModel.hasDecodedFieldColumn(key: field.key) ? "Added" : "Add column") {
                viewModel.addDecodedFieldColumn(key: field.key, title: field.label)
            }
            .controlSize(.small)
            .disabled(viewModel.hasDecodedFieldColumn(key: field.key))
        }
        .padding(.horizontal, DesignToken.Spacing.card)
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(
                "\(DecodedFieldCatalog.allKeys(in: viewModel.networks).count) distinct keys across \(viewModel.networks.count) networks"
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            Spacer()
            Button("Export all fields CSV…") { viewModel.exportDecodedFieldsCSV() }
                .disabled(viewModel.networks.isEmpty)
        }
        .padding(.horizontal, DesignToken.Spacing.card)
        .padding(.vertical, DesignToken.Spacing.small)
    }
}
