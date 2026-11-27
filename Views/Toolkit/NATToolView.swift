import AppKit
import SwiftUI

/// P4.4: what the router does to this Mac's UDP packets, measured with two
/// public STUN servers from one socket.
struct NATToolView: View {
    @ObservedObject var model: NATToolModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.card) {
            controls
            if let error = model.errorMessage {
                ToolkitErrorBanner(message: error)
            }
            if let report = model.report {
                verdictCard(report)
                probeTable(report)
            } else if !model.isRunning {
                ToolkitEmptyState(
                    icon: "network",
                    title: "Check the router",
                    message:
                        "Sends STUN binding requests to two public servers from one socket and reports the mapping the router gives this Mac."
                )
            }
        }
        // Without this the stack sizes to its widest card and the window
        // centres the whole screen, which put the target field in the middle.
        .frame(maxWidth: .infinity, alignment: .leading)
        .appContentPadding()
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: DesignToken.Spacing.small) {
                TextField("stun.l.google.com:19302", text: $model.server)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                AppButton(
                    localized: model.isRunning ? String(localized: "Checking…") : String(localized: "Run test"),
                    tone: .primary, isEnabled: !model.isRunning
                ) {
                    model.run()
                }
                AppButton("Copy", tone: .secondary) { model.copy() }
                    .disabled(model.report == nil)
                AppButton("Clear", tone: .quiet) { model.clear() }
                    .disabled(model.report == nil && model.errorMessage == nil)
                Spacer()
                Text("Only public STUN servers are contacted; nothing is sent anywhere else.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func verdictCard(_ report: NATReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    ToolkitSectionLabel(text: "Result")
                    Spacer()
                    ToolkitStatusPill(text: report.verdict.title, tone: tone(for: report.verdict))
                }
                Text(report.verdict.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack(alignment: .top, spacing: 28) {
                    fact("Local address", report.localEndpoint.label)
                    fact("External address", report.externalEndpoint?.label ?? "—")
                    fact("Mapping", report.mapping.label)
                    fact("Filtering", report.filtering.label)
                    fact("Port preserved", report.portPreserved ? "Yes" : "No")
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func probeTable(_ report: NATReport) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ToolkitSectionLabel(text: "Probes")
                    .padding(.horizontal, DesignToken.Spacing.card)
                    .padding(.top, DesignToken.Spacing.medium)
                    .padding(.bottom, DesignToken.Spacing.tight)
                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "server", title: String(localized: "Server"), minWidth: 220,
                            value: { .text($0.server.label) }
                        ) { probe in
                            Text(probe.server.label)
                                .font(.caption.monospaced())
                        },
                        AppTableColumn(
                            id: "mapped", title: String(localized: "Mapped to"), minWidth: 220,
                            value: { .text($0.answerText) }
                        ) { probe in
                            Text(probe.answerText)
                                .font(.caption.monospaced())
                                .foregroundColor(probe.failure == nil ? .primary : .secondary)
                        },
                        AppTableColumn(
                            id: "time", title: String(localized: "Time"), minWidth: 70,
                            value: { .number($0.milliseconds ?? 0) }
                        ) { probe in
                            Text(probe.milliseconds.map { "\($0) ms" } ?? "—")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        },
                    ],
                    rows: report.probes, initialKey: "server"
                )
                .frame(height: ToolkitTableHeight.rows(report.probes.count, row: 26, header: 40))
            }
        }
    }

    private func fact(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func tone(for verdict: NATVerdict) -> ToolkitTone {
        switch verdict {
        case .direct, .cone: return .good
        case .symmetric: return .warning
        case .blocked: return .bad
        case .unknown: return .neutral
        }
    }
}
