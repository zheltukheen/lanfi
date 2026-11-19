import AppKit
import SwiftUI

struct WhoisToolView: View {
    @ObservedObject var model: WhoisToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let report = model.report {
                    header(report)
                    details(report)
                    events(report)
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "Look up a domain",
                        message:
                            "Reads the registration over RDAP: registrar, statuses, dates, nameservers and events. No Terminal."
                    )
                }
            }
            .appContentPadding()
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                ToolTargetField(
                    text: $model.query, placeholder: "Domain or IP",
                    onSubmit: { model.run() }
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .onSubmit { model.run() }
                AppButton("Look Up", tone: .primary) { model.run() }
                    .disabled(model.isRunning)
                AppButton("Copy", tone: .secondary) { copy() }
                    .disabled(model.report == nil)
                AppButton("Clear", tone: .quiet) { model.clear() }
                    .disabled(model.report == nil)
                Spacer()
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Looking up…") }
        guard let report = model.report else { return String(localized: "Ready") }
        return String(
            format: String(localized: "%lld statuses"), report.statuses.count)
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        return model.report == nil ? .neutral : .good
    }

    private func header(_ report: WhoisReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(report.name)
                        .font(.title3.bold())
                    Spacer()
                    Text(report.objectType.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                if let registrar = report.registrar {
                    Label(registrar, systemImage: "building.2")
                        .font(.callout)
                }
                if let handle = report.handle {
                    Text("Handle: \(handle)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                if !report.statuses.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(report.statuses, id: \.self) { status in
                            Text(status)
                                .font(.caption2)
                                .padding(.horizontal, DesignToken.Spacing.tight)
                                .padding(.vertical, 2)
                                .background(
                                    Color.orange.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: DesignToken.Radius.badge))
                        }
                    }
                }
            }
        }
    }

    private func details(_ report: WhoisReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Dates")
                detailRow("Registered", report.registrationDate)
                detailRow("Expires", report.expirationDate)
                detailRow("Last changed", report.lastChangedDate)
                Divider()
                ToolkitSectionLabel(text: "Nameservers")
                if report.nameservers.isEmpty {
                    Text("None reported")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(report.nameservers, id: \.self) { nameserver in
                        Text(nameserver)
                            .font(.caption.monospaced())
                    }
                }
            }
        }
    }

    private func events(_ report: WhoisReport) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Events")
                    Spacer()
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)
                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "event", title: "Event", minWidth: 180,
                            value: { .text($0.action) }
                        ) { event in
                            Text(event.action).font(.caption)
                        },
                        AppTableColumn(
                            id: "date", title: "Date", minWidth: 120,
                            value: { .number($0.date?.timeIntervalSince1970) }
                        ) { event in
                            Text(
                                event.date.map {
                                    $0.formatted(date: .abbreviated, time: .omitted)
                                } ?? "—"
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        },
                    ],
                    rows: report.events, initialKey: "date"
                )
                .frame(height: min(CGFloat(report.events.count) * 26 + 40, 260))
            }
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ date: Date?) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(date?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                .font(.caption.monospacedDigit())
        }
    }

    private func copy() {
        guard let report = model.report else { return }
        let text = """
            LanFi Whois \(report.query)
            Name: \(report.name)
            Registrar: \(report.registrar ?? "—")
            Statuses: \(report.statuses.joined(separator: ", "))
            Registered: \(report.registrationDate?.formatted() ?? "—")
            Expires: \(report.expirationDate?.formatted() ?? "—")
            Nameservers: \(report.nameservers.joined(separator: ", "))
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
