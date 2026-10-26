import SwiftUI

struct ProtocolsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    private var coverage: ProtocolCoverage {
        ProtocolAnalyzer.coverage(for: viewModel.networks)
    }

    private var selectedProfile: ProtocolProfile? {
        guard let network = viewModel.selectedNetwork else { return nil }
        return ProtocolAnalyzer.profile(for: network, metrics: viewModel.metrics(for: network))
    }

    var body: some View {
        Group {
            if let profile = selectedProfile {
                selectedContent(profile)
            } else {
                overviewContent
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Selected network

    private func selectedContent(_ profile: ProtocolProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                protocolHeader(profile)

                if !profile.warnings.isEmpty {
                    warningsView(profile.warnings)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(Array(profile.blocks.enumerated()), id: \.element.id) { index, block in
                        ProtocolBlockCard(block: block, index: index + 1, band: profile.band)
                    }
                }
            }
            .padding(14)
        }
    }

    private func protocolHeader(_ profile: ProtocolProfile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Selected network", systemImage: "cursorarrow.click")
                    .font(.caption2.bold())
                    .foregroundColor(.accentColor)
                HStack(spacing: 8) {
                    Text(profile.title)
                        .font(.title3.bold())
                        .lineLimit(1)
                    bandBadge(profile.band)
                }
                Text(profile.subtitle)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Text(profile.formatLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Protocol blocks")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(profile.blocks.count)")
                    .font(.title2.bold())
                    .foregroundColor(.accentColor)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [bandColor(profile.band).opacity(0.16), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(bandColor(profile.band).opacity(0.25), lineWidth: 1)
        )
    }

    private func warningsView(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                "\(warnings.count) protocol warning\(warnings.count == 1 ? "" : "s")",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption.bold())
            .foregroundColor(.orange)
            ForEach(warnings.prefix(3), id: \.self) { warning in
                Text(warning)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - No selection

    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protocols overview")
                        .font(.headline)
                    Text(
                        "All \(coverage.networkCount) visible networks are summarised here. Select a row to inspect one network in seven protocol blocks."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    coverageCard("Networks", value: "\(coverage.networkCount)", tint: .accentColor)
                    coverageCard("6 GHz", value: "\(coverage.sixGHzCount)", tint: .purple)
                    coverageCard("Wi-Fi 7", value: "\(coverage.wiFi7Count)", tint: .blue)
                    coverageCard("PMF", value: "\(coverage.pmfCount)", tint: .green)
                    coverageCard("WPS", value: "\(coverage.wpsCount)", tint: coverage.wpsCount > 0 ? .orange : .green)
                    coverageCard("Open", value: "\(coverage.openCount)", tint: coverage.openCount > 0 ? .red : .green)
                }

                HStack(alignment: .top, spacing: 14) {
                    distributionCard(
                        title: "PHY generations",
                        subtitle: "Highest advertised 802.11 mode",
                        values: coverage.generationCounts,
                        tint: .blue
                    )
                    distributionCard(
                        title: "Security modes",
                        subtitle: "Networks by advertised security",
                        values: coverage.securityCounts,
                        tint: .green
                    )
                    distributionCard(
                        title: "Bands",
                        subtitle: "Observed spectrum",
                        values: coverage.bandCounts,
                        tint: .orange
                    )
                }

                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text("Select a network to inspect its protocol blocks")
                        .font(.headline)
                    Text(
                        "Radio, security, roaming, spectrum, network format and vendor capabilities are decoded separately."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .padding(14)
        }
    }

    private func coverageCard(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private func distributionCard(
        title: String,
        subtitle: String,
        values: [String: Int],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold())
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
            ForEach(values.sorted { $0.value > $1.value }, id: \.key) { key, count in
                HStack(spacing: 6) {
                    Text(key)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer()
                    Text("\(count)")
                        .font(.caption2.bold())
                        .foregroundColor(tint)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 318, maxHeight: 318, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private func bandBadge(_ band: WiFiBand) -> some View {
        Text(band.label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(bandColor(band))
            .background(bandColor(band).opacity(0.12))
            .clipShape(Capsule())
    }

    private func bandColor(_ band: WiFiBand) -> Color {
        switch band {
        case .band24: return .orange
        case .band5: return .blue
        case .band6: return .purple
        case .unknown: return .gray
        }
    }
}

private struct ProtocolBlockCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let block: ProtocolBlock
    let index: Int
    let band: WiFiBand

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Image(systemName: block.systemImage)
                    .foregroundColor(statusColor)
                    .frame(width: 18)
                Text(LocalizedStringKey(block.title))
                    .font(.caption.bold())
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            Text(LocalizedStringKey(block.subtitle))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(block.facts.prefix(6)) { fact in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(factColor(fact.status))
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LocalizedStringKey(fact.label))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(TechnicalLocalizer.localize(fact.value))
                                .font(.caption)
                                .lineLimit(2)
                            if let detail = fact.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 318, maxHeight: 318, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(statusColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch block.status {
        case .good: return .green
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    private func factColor(_ status: ProtocolFactStatus) -> Color {
        switch status {
        case .good: return .green
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}
