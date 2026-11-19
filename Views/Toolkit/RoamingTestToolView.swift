import SwiftUI

/// Roaming test MVP (P1.2): what the connected BSSID advertises (802.11k/v/r),
/// how the client has moved between BSSIDs, and whether it is sticky or should
/// be band-steered.
struct RoamingTestToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel

    private enum SortKey: String, CaseIterable, Identifiable {
        case when, from, to, signal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .when: return String(localized: "When")
            case .from: return String(localized: "From")
            case .to: return String(localized: "To")
            case .signal: return String(localized: "Signal")
            }
        }
    }

    @State private var sortKey: SortKey = .when
    @State private var sortAscending = false

    private func sortedTransitions(_ rows: [RoamTransition]) -> [RoamTransition] {
        let ordered = rows.sorted { lhs, rhs in
            switch sortKey {
            case .when: return lhs.at < rhs.at
            case .from:
                return lhs.fromBSSID.localizedStandardCompare(rhs.fromBSSID) == .orderedAscending
            case .to: return lhs.toBSSID.localizedStandardCompare(rhs.toBSSID) == .orderedAscending
            case .signal: return lhs.rssiAfter < rhs.rssiAfter
            }
        }
        return sortAscending ? ordered : ordered.reversed()
    }
    @State private var walkStart: Date?

    private var samples: [MonitorSample] {
        guard let walkStart else { return analyzer.monitor.samples }
        return analyzer.monitor.samples.filter { $0.at >= walkStart }
    }

    private var assessment: RoamingAssessment? {
        RoamingAnalyzer.assess(
            connected: analyzer.connectedNetwork,
            visible: analyzer.networks,
            samples: samples
        )
    }

    private var roamEvents: [MonitorEvent] {
        let start = walkStart ?? .distantPast
        return analyzer.monitor.events
            .filter { ($0.kind == .roamed || $0.kind == .roamingFailure) && $0.at >= start }
            .suffix(20)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let assessment {
                    currentLink(assessment)
                    capabilities(assessment)
                    verdicts(assessment)
                    transitions(assessment)
                } else {
                    ToolkitEmptyState(
                        icon: "wifi.slash",
                        title: "No connected network",
                        message:
                            "Join a Wi-Fi network to see its roaming capabilities and BSSID transitions."
                    )
                }
                events
            }
            .appContentPadding()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if let walkStart {
                ToolkitStatusPill(
                    text: "Walk test since \(walkStart.formatted(date: .omitted, time: .shortened))",
                    tone: .running)
            }
            Spacer()
            AppButton("Start Walk Test", systemImage: "figure.walk") {
                walkStart = Date()
            }
            AppButton(
                "Use all history", systemImage: "clock.arrow.circlepath", tone: .quiet,
                isEnabled: walkStart != nil
            ) {
                walkStart = nil
            }
        }
    }

    private func currentLink(_ assessment: RoamingAssessment) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "wifi")
                    .font(.system(size: 28))
                    .foregroundColor(AppPalette.quality(quality(for: assessment.rssi)))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(assessment.ssid).font(.title3.bold())
                    Text(assessment.bssid)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    Text("\(assessment.rssi) dBm · \(samples.count) samples in window")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    ToolkitStatusPill(
                        text: assessment.failureCount == 0
                            ? "No failed roams" : "\(assessment.failureCount) failed roams",
                        tone: assessment.failureCount == 0 ? .good : .bad)
                    if let last = assessment.lastRoamAt {
                        Text("Last roam \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func capabilities(_ assessment: RoamingAssessment) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ToolkitSectionLabel(text: "Fast roaming")
                    Spacer()
                    ToolkitStatusPill(
                        text: assessment.capabilities.summary,
                        tone: assessment.capabilities.supportedCount > 0 ? .good : .warning)
                }
                HStack(spacing: 24) {
                    ToolkitMetric(
                        title: "802.11r", value: assessment.capabilities.fastTransition ? "Yes" : "No",
                        tint: assessment.capabilities.fastTransition ? .green : .secondary)
                    ToolkitMetric(
                        title: "802.11k", value: assessment.capabilities.radioMeasurements ? "Yes" : "No",
                        tint: assessment.capabilities.radioMeasurements ? .green : .secondary)
                    ToolkitMetric(
                        title: "802.11v", value: assessment.capabilities.bssTransition ? "Yes" : "No",
                        tint: assessment.capabilities.bssTransition ? .green : .secondary)
                    Spacer()
                }
                Text(
                    "Without 802.11k/v the client scans on its own and decides when to roam; without 802.11r the handshake is repeated on every move."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private func verdicts(_ assessment: RoamingAssessment) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Verdicts")
                if assessment.verdicts.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle").foregroundColor(.green)
                        Text("The client is on a reasonable BSSID for this signal level.")
                            .font(.caption)
                    }
                } else {
                    ForEach(assessment.verdicts) { verdict in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: verdict.kind))
                                .foregroundColor(tint(for: verdict.kind))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verdict.title).font(.caption.bold())
                                Text(verdict.detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func transitions(_ assessment: RoamingAssessment) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "BSSID transitions")
                    if !assessment.transitions.isEmpty {
                        TableSortControl(
                            options: SortKey.allCases.map { ($0, $0.title) },
                            selection: $sortKey, ascending: $sortAscending)
                    }
                    Spacer()
                    Text("\(assessment.transitions.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                if assessment.transitions.isEmpty {
                    Text("No BSSID changes in the window yet. Start a walk test and move around the coverage area.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, DesignToken.Spacing.card)
                        .padding(.bottom, DesignToken.Spacing.card)
                } else {
                    Table(sortedTransitions(Array(assessment.transitions.prefix(20)))) {
                        TableColumn("When") { transition in
                            Text(transition.at.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                        }
                        .width(AppColumnWidth.compact)
                        TableColumn("From") { transition in
                            Text(transition.fromBSSID).font(.caption2.monospaced())
                        }
                        TableColumn("To") { transition in
                            Text(transition.toBSSID).font(.caption2.monospaced())
                        }
                        TableColumn("Signal") { transition in
                            Text("\(transition.rssiBefore) → \(transition.rssiAfter) dBm")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(transition.isFailure ? .red : .secondary)
                        }
                        .width(AppColumnWidth.wide)
                    }
                    .frame(
                        height: ToolkitTableHeight.rows(
                            min(assessment.transitions.count, 20), row: 26, header: 36,
                            minimum: 170, maximum: 300))
                }
            }
        }
    }

    private var events: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Monitor roam events")
                    Spacer()
                    Text("\(roamEvents.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)
                if roamEvents.isEmpty {
                    Text("No roam events recorded by the Wi-Fi Monitor yet.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, DesignToken.Spacing.card)
                        .padding(.bottom, DesignToken.Spacing.card)
                } else {
                    ForEach(Array(roamEvents.reversed())) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(
                                systemName: event.kind == .roamingFailure
                                    ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath"
                            )
                            .foregroundColor(event.kind == .roamingFailure ? .red : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.detail).font(.caption2)
                                Text(event.at.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, DesignToken.Spacing.card)
                        .padding(.vertical, 3)
                    }
                    .padding(.bottom, DesignToken.Spacing.compact)
                }
            }
        }
    }

    private func icon(for kind: RoamingVerdict.Kind) -> String {
        switch kind {
        case .sticky: return "pin.slash"
        case .bandSteering: return "arrow.left.arrow.right"
        case .weak: return "exclamationmark.triangle"
        }
    }

    private func tint(for kind: RoamingVerdict.Kind) -> Color {
        switch kind {
        case .sticky: return AppPalette.danger
        case .bandSteering: return AppPalette.info
        case .weak: return AppPalette.warning
        }
    }

    private func quality(for rssi: Int) -> Int {
        max(0, min(100, (rssi + 100) * 2))
    }
}
