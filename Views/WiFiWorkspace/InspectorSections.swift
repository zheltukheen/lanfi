import AppKit
import SwiftUI

struct MultiSelectionInspector: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var bulkAlias = ""
    @State private var bulkNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.accentColor)
                Text("\(viewModel.selectedNetworkIds.count) networks selected")
                    .font(.headline)
            }
            Text("Use ⌘-click or ⇧-click in the table to extend the selection.")
                .font(.caption)
                .foregroundColor(.secondary)

            let selected = viewModel.selectedNetworks
            VStack(alignment: .leading, spacing: 4) {
                ForEach(selected.prefix(8)) { network in
                    HStack {
                        Text(network.displaySSID).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(network.signal) dBm").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if selected.count > 8 {
                    Text("+ \(selected.count - 8) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Comparison").font(.caption.bold())
                NetworkComparisonTable(viewModel: viewModel, networks: selected)
                    .frame(maxHeight: 220)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bulk annotation").font(.caption.bold())
                TextField("Alias for all selected", text: $bulkAlias)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes for all selected", text: $bulkNotes)
                    .textFieldStyle(.roundedBorder)
                Button("Apply to \(selected.count) selected") {
                    viewModel.applyBulkAnnotation(
                        alias: bulkAlias, notes: bulkNotes, to: viewModel.selectedNetworkIds
                    )
                }
                .controlSize(.small)
                .disabled(selected.isEmpty)
            }

            HStack {
                Button {
                    viewModel.copySelectedNetworks()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    viewModel.exportSelectedCSV()
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
                Button {
                    viewModel.exportSelectedJSON()
                } label: {
                    Label("JSON", systemImage: "curlybraces")
                }
            }
            .controlSize(.small)

            Button("Clear Selection") {
                viewModel.setSelection(ids: [], primary: nil)
            }
            .controlSize(.small)
        }
        .padding(14)
    }
}

struct QualityInspectorSection: View {
    let metrics: NetworkMetrics
    let recommendation: ChannelRecommendation?

    var body: some View {
        GroupBox("Quality") {
            VStack(alignment: .leading, spacing: 10) {
                QualityScoreView(score: metrics.qualityScore)
                ScoreRow(label: "Signal", score: metrics.signalScore)
                if let snr = metrics.snrScore {
                    ScoreRow(label: "SNR", score: snr)
                }
                ScoreRow(label: "Channel congestion", score: metrics.congestionScore)
                ScoreRow(label: "Security", score: metrics.securityScore)
                HStack {
                    Label("\(metrics.overlappingCount) overlapping", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Label("\(metrics.coChannelCount) co-channel", systemImage: "antenna.radiowaves.left.and.right")
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                if let recommendation {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "wand.and.stars").foregroundColor(.accentColor)
                        Text(
                            "Best \(recommendation.band.label): channel \(recommendation.channel) · \(recommendation.widthMHz) MHz"
                        )
                        .font(.caption)
                        Spacer()
                        Text("\(recommendation.score)")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    if recommendation.isPreferredScanningChannel {
                        Label(
                            "PSC channel — active scans probe it, so 6 GHz clients find it",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }

                if let issue = metrics.issues.first {
                    HStack(alignment: .top, spacing: 6) {
                        Image(
                            systemName: issue.severity == .critical
                                ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(issue.severity == .critical ? .red : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.caption.bold())
                            Text(issue.detail).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
    }
}

struct ChannelAdviceSection: View {
    let advice: ChannelAdvice

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Current ch \(advice.currentChannel) · \(advice.currentWidthMHz) MHz")
                        .font(.caption)
                    Spacer()
                    if let score = advice.currentScore {
                        Text("\(score)/100").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if advice.shouldChange, let target = advice.recommendation {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Text("Change to channel \(target.channel) · \(target.widthMHz) MHz")
                            .font(.caption.bold())
                        Spacer()
                        Text("\(target.score)/100").font(.caption.bold()).foregroundColor(.green)
                    }
                    if target.isDFS {
                        Label("DFS channel — verify router/region support", systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundColor(.orange)
                    }
                } else {
                    Label("Keep current channel", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold()).foregroundColor(.green)
                }
                Text(advice.reason).font(.caption2).foregroundColor(.secondary)
                if let model = advice.routerModel {
                    Text("Router model: \(model)").font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            .padding(4)
        } label: {
            Label("Channel recommendation", systemImage: "wand.and.stars")
        }
    }
}

struct SignalBadge: View {
    let rssi: Int
    let label: String
    let unit: String

    var color: Color {
        if rssi > -50 { return .green } else if rssi > -70 { return .yellow } else { return .red }
    }

    var body: some View {
        VStack {
            Text(label)
                .font(.title3).bold()
                .foregroundColor(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
