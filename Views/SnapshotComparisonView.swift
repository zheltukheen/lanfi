import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// G5: save the scan under a name, then compare two snapshots to see what
/// changed — the before/after story an AP firmware update or a channel change
/// needs. Local files only.
struct SnapshotComparisonView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    @State private var snapshots: [ScanSnapshot] = []
    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var label = ""
    @State private var errorMessage: String?

    private let store = ScanSnapshotStore()

    private var before: ScanSnapshot? { snapshots.first { $0.id == beforeID } }
    private var after: ScanSnapshot? { snapshots.first { $0.id == afterID } }

    private var diff: ScanSnapshotDiff? {
        guard let before, let after, before.id != after.id else { return nil }
        return ScanSnapshotDiff.compare(before: before, after: after)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if snapshots.count < 2 {
                emptyState
            } else {
                comparison
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .lanFiSnapshotsChanged)) { _ in
            reload()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan snapshots")
                    .font(.title3.bold())
                Text(
                    "Save the visible scan under a name, then compare two of them. A is the older scan, B the newer one."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            TextField("Snapshot name", text: $label)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button("Save current scan") { saveCurrent() }
                .disabled(viewModel.networks.isEmpty)
                .help(
                    viewModel.networks.isEmpty
                        ? "Run a scan first" : "Saves the \(viewModel.networks.count) visible networks")
        }
        .padding(DesignToken.Spacing.card)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Two snapshots are needed to compare")
                .font(.headline)
            Text(
                "Take one before a change and one after it — an AP firmware update, a channel move, a new mesh node. Each snapshot stores BSSID, SSID, band, channel, width, security, signal and vendor."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
            if !snapshots.isEmpty {
                Text("Saved: \(snapshots.count) of 2 needed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            pickers
            if let diff {
                summary(diff)
                Divider()
                diffList(diff)
            } else {
                Text("Pick two different snapshots to see the difference.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var pickers: some View {
        HStack(spacing: 14) {
            Picker("A · before", selection: $beforeID) {
                ForEach(snapshots) { snapshot in
                    Text(snapshot.label).tag(Optional(snapshot.id))
                }
            }
            .frame(maxWidth: 260)
            Picker("B · after", selection: $afterID) {
                ForEach(snapshots) { snapshot in
                    Text(snapshot.label).tag(Optional(snapshot.id))
                }
            }
            .frame(maxWidth: 260)
            Spacer()
            if let after {
                Button("Delete B") { delete(after) }
                    .help("Removes \(after.label) from disk")
            }
        }
        .padding(.horizontal, DesignToken.Spacing.card)
        .padding(.vertical, DesignToken.Spacing.medium)
    }

    private func summary(_ diff: ScanSnapshotDiff) -> some View {
        HStack(spacing: 22) {
            metric("Added", diff.added.count, AppPalette.ok)
            metric("Removed", diff.removed.count, AppPalette.danger)
            metric("Changed", diff.changed.count, AppPalette.warning)
            Spacer()
            if let before, let after {
                Text(
                    "\(before.label) → \(after.label) · ±\(diff.rssiThreshold) dBm counts as a signal change"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, DesignToken.Spacing.card)
        .padding(.bottom, DesignToken.Spacing.small)
    }

    private func metric(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit())
                .foregroundColor(value == 0 ? .secondary : tint)
        }
    }

    private func diffList(_ diff: ScanSnapshotDiff) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if diff.isEmpty {
                    Text("No structural difference: same BSSIDs, channels, widths and security.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(DesignToken.Spacing.card)
                }
                if !diff.added.isEmpty {
                    sectionHeader("Added")
                    ForEach(diff.added) { network in
                        networkRow(network, tint: AppPalette.ok)
                    }
                    Divider()
                }
                if !diff.removed.isEmpty {
                    sectionHeader("Removed")
                    ForEach(diff.removed) { network in
                        networkRow(network, tint: AppPalette.danger)
                    }
                    Divider()
                }
                if !diff.changed.isEmpty {
                    sectionHeader("Changed")
                    ForEach(diff.changed) { change in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundColor(AppPalette.warning)
                                .frame(width: 18)
                            Text(change.ssid)
                                .font(.caption)
                                .frame(width: 160, alignment: .leading)
                                .lineLimit(1)
                            Text(change.bssid)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .frame(width: 130, alignment: .leading)
                            Text(change.summary)
                                .font(.caption2)
                            Spacer()
                        }
                        .padding(.horizontal, DesignToken.Spacing.card)
                        .padding(.vertical, 3)
                    }
                    Divider()
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, DesignToken.Spacing.card)
            .padding(.top, DesignToken.Spacing.small)
            .padding(.bottom, 2)
    }

    private func networkRow(_ network: ScanSnapshotNetwork, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(network.ssid.isEmpty ? "Hidden" : network.ssid)
                .font(.caption)
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
            Text(network.bssid)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text("\(network.band) · ch \(network.channel) · \(network.widthMHz) MHz")
                .font(.caption2)
                .frame(width: 150, alignment: .leading)
            Text(network.security)
                .font(.caption2)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Text("\(network.rssi) dBm")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, DesignToken.Spacing.card)
        .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else {
                Text("\(snapshots.count) saved locally · \(ScanSnapshotStore.defaultURL.path)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Export diff CSV…") { exportCSV() }
                .disabled(diff == nil)
        }
        .padding(.horizontal, DesignToken.Spacing.card)
        .padding(.vertical, DesignToken.Spacing.small)
    }

    // MARK: - Actions

    private func reload() {
        snapshots = store.load().sorted { $0.createdAt < $1.createdAt }
        if beforeID == nil || !snapshots.contains(where: { $0.id == beforeID }) {
            beforeID = snapshots.first?.id
        }
        if afterID == nil || !snapshots.contains(where: { $0.id == afterID }) {
            afterID = snapshots.last?.id
        }
        if snapshots.count >= 2, beforeID == afterID {
            beforeID = snapshots.dropLast().last?.id ?? snapshots.first?.id
        }
    }

    private func saveCurrent() {
        guard !viewModel.networks.isEmpty else { return }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = ScanSnapshotBuilder.snapshot(
            label: name.isEmpty ? ScanSnapshotActions.defaultLabel() : name,
            networks: viewModel.networks)
        do {
            try store.add(snapshot)
            label = ""
            errorMessage = nil
            reload()
            afterID = snapshot.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ snapshot: ScanSnapshot) {
        do {
            try store.delete(id: snapshot.id)
            errorMessage = nil
            beforeID = nil
            afterID = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCSV() {
        guard let diff else { return }
        let panel = NSSavePanel()
        panel.title = "Export snapshot diff"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LanFi-snapshot-diff.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try diff.csv.write(to: url, atomically: true, encoding: .utf8)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
