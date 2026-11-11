import Charts
import SwiftUI

struct UptimeToolView: View {
    @ObservedObject var monitor: UptimeMonitor
    @State private var selectedID: UUID?
    @State private var showingAdd = false
    @State private var period: UptimePeriod = .day

    private var selectedTarget: UptimeTarget? {
        if let selectedID, let target = monitor.targets.first(where: { $0.id == selectedID }) {
            return target
        }
        return monitor.targets.first
    }

    var body: some View {
        HStack(spacing: 0) {
            targetList
                .frame(width: 250)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingAdd) {
            UptimeAddTargetView { name, address, kind, interval in
                monitor.add(name: name, address: address, kind: kind, intervalMinutes: interval)
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = monitor.targets.first?.id }
        }
    }

    private var targetList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Targets")
                    .font(.caption.bold())
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a target")
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            if monitor.targets.isEmpty {
                Text("Add a website or server to watch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(monitor.targets) { target in
                            targetRow(target)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Divider()
            Button {
                Task { await monitor.checkAllNow() }
            } label: {
                Label("Check All Now", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .disabled(monitor.isChecking || monitor.targets.isEmpty)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func targetRow(_ target: UptimeTarget) -> some View {
        let state = monitor.state(for: target)
        let selected = selectedTarget?.id == target.id
        return Button {
            selectedID = target.id
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(tone(for: state.isUp).color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(target.address)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(state.uptimePercent.map { String(format: "%.1f%%", $0) } ?? "—")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let target = selectedTarget {
            let state = monitor.state(for: target)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(target, state: state)
                    metrics(state)
                    chartCard(target, state: state)
                    checksTable(state)
                }
                .padding(18)
            }
        } else {
            ToolkitEmptyState(
                icon: "clock.badge.checkmark",
                title: "Watch a service",
                message:
                    "Add a website, API or TCP port. Uptime Monitor checks it on a schedule and notifies you when it goes down or comes back."
            )
        }
    }

    private func header(_ target: UptimeTarget, state: UptimeTargetState) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: target.kindIcon)
                    .font(.system(size: 30))
                    .foregroundColor(tone(for: state.isUp).color)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(.title3.bold())
                    Text(target.address)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    if let detail = state.lastCheck?.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ToolkitStatusPill(
                        text: state.isUp.map { $0 ? String(localized: "Up") : String(localized: "Down") }
                            ?? String(localized: "No checks"),
                        tone: tone(for: state.isUp))
                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { target.enabled },
                            set: { monitor.setEnabled($0, for: target) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
            }
        }
    }

    private func metrics(_ state: UptimeTargetState) -> some View {
        ToolkitCard {
            HStack(spacing: 20) {
                ToolkitMetric(
                    title: "Uptime",
                    value: state.uptimePercent.map { String(format: "%.2f%%", $0) } ?? "—",
                    tint: (state.uptimePercent ?? 100) >= 99 ? .green : .orange)
                ToolkitMetric(
                    title: "Average latency",
                    value: ToolkitFormat.milliseconds(state.averageLatencyMilliseconds))
                ToolkitMetric(title: "Outages", value: "\(state.outageCount)")
                ToolkitMetric(title: "Checks", value: "\(state.checks.count)")
                ToolkitMetric(
                    title: "Last check",
                    value: state.lastCheck?.at.formatted(date: .omitted, time: .shortened)
                        ?? "—")
                Spacer()
                Button {
                    Task { await monitor.checkNow(state.target.id) }
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .disabled(monitor.isChecking)
            }
        }
    }

    private func chartCard(_ target: UptimeTarget, state: UptimeTargetState) -> some View {
        let cutoff = Date().addingTimeInterval(-period.seconds)
        let checks = state.checks.filter { $0.at >= cutoff }
        return ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ToolkitSectionLabel(text: "Latency")
                    Spacer()
                    Picker("Period", selection: $period) {
                        ForEach(UptimePeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
                if checks.isEmpty {
                    Text("No checks in this period yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    Chart {
                        ForEach(checks) { check in
                            if check.isUp, let latency = check.latencyMilliseconds {
                                LineMark(
                                    x: .value("Time", check.at),
                                    y: .value("Latency", latency)
                                )
                                .interpolationMethod(.monotone)
                                PointMark(
                                    x: .value("Time", check.at),
                                    y: .value("Latency", latency)
                                )
                                .symbolSize(18)
                            }
                            if !check.isUp {
                                PointMark(
                                    x: .value("Time", check.at),
                                    y: .value("Latency", 0)
                                )
                                .foregroundStyle(.red)
                                .symbolSize(22)
                            }
                        }
                    }
                    .chartYAxisLabel("ms")
                    .frame(height: 190)
                }
            }
        }
    }

    private func checksTable(_ state: UptimeTargetState) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Recent checks")
                    Spacer()
                    Button(role: .destructive) {
                        monitor.remove(state.target)
                        selectedID = nil
                    } label: {
                        Label("Remove target", systemImage: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                if state.checks.isEmpty {
                    Text("Waiting for the first check.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                } else {
                    Table(Array(state.checks.suffix(20).reversed())) {
                        TableColumn("When") { check in
                            Text(check.at.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                        }
                        TableColumn("Status") { check in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(check.isUp ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(check.isUp ? String(localized: "Up") : String(localized: "Down"))
                                    .font(.caption)
                            }
                        }
                        .width(70)
                        TableColumn("Latency") { check in
                            Text(ToolkitFormat.milliseconds(check.latencyMilliseconds))
                                .font(.caption.monospacedDigit())
                        }
                        .width(80)
                        TableColumn("Detail") { check in
                            Text(check.detail ?? "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: min(CGFloat(min(state.checks.count, 20)) * 24 + 30, 260))
                }
            }
        }
    }

    private func tone(for isUp: Bool?) -> ToolkitTone {
        guard let isUp else { return .neutral }
        return isUp ? .good : .bad
    }
}

enum UptimePeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        }
    }
}

private struct UptimeAddTargetView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, String, UptimeTargetKind, Int) -> Bool

    @State private var name = ""
    @State private var address = ""
    @State private var kind: UptimeTargetKind = .http
    @State private var intervalMinutes = 5
    @State private var errorMessage: String?

    private var placeholder: String {
        switch kind {
        case .http: return "https://example.com/health"
        case .tcp: return "example.com:5432"
        case .tls: return "example.com:443"
        case .dns, .mail: return "example.com"
        }
    }

    private var validationMessage: String {
        switch kind {
        case .http: return String(localized: "Enter a valid HTTP or HTTPS URL.")
        case .tcp: return String(localized: "Enter host:port for the TCP target.")
        case .tls: return String(localized: "Enter host[:port] for the TLS target.")
        case .dns: return String(localized: "Enter a hostname for the DNS target.")
        case .mail: return String(localized: "Enter a domain for the mail target.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Target")
                .font(.title3.bold())
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name").font(.caption).foregroundColor(.secondary)
                    TextField("API Server", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Kind").font(.caption).foregroundColor(.secondary)
                    Picker("Kind", selection: $kind) {
                        ForEach(UptimeTargetKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Address").font(.caption).foregroundColor(.secondary)
                    TextField(placeholder, text: $address)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Every").font(.caption).foregroundColor(.secondary)
                    Picker("Interval", selection: $intervalMinutes) {
                        Text("1 min").tag(1)
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("6 hours").tag(360)
                        Text("1 day").tag(1_440)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Spacer()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add") {
                    if onAdd(name, address, kind, intervalMinutes) {
                        dismiss()
                    } else {
                        errorMessage = validationMessage
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460, height: 300)
    }
}
