import SwiftUI

/// P0.2: pick active, passive or directed scanning, inspect the 6 GHz PSC/RNR
/// channel plan and follow a passive run. Unsupported hardware is explained
/// here instead of failing silently.
struct PassiveScanSheet: View {
    @ObservedObject var scan: PassiveScanViewModel
    @Environment(\.dismiss) private var dismiss

    private let chipColumns = [GridItem(.adaptive(minimum: 64), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
            AppSheetHeader(
                icon: "dot.radiowaves.left.and.right",
                title: "Scan mode",
                subtitle:
                    "Passive listening finds the 6 GHz and beacon-only access points macOS active scans skip."
            ) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Picker(
                "Scan mode",
                selection: Binding(
                    get: { scan.mode }, set: { scan.selectMode($0) })
            ) {
                ForEach(ScanMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            supportBlock
            rateCard
            planCard
            progressCard
            footer
        }
        .appSheet(width: 780, minHeight: 580)
        .onAppear { scan.refreshHardware() }
    }

    // MARK: - Support

    @ViewBuilder
    private var supportBlock: some View {
        let support = scan.support
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    SectionLabel(text: scan.mode.title)
                    if let badge = support.badge {
                        StatusPill(
                            text: badge,
                            tone: support.isUsable ? .warning : .bad,
                            icon: support.isUsable ? "exclamationmark.triangle" : "xmark.octagon")
                    }
                    Spacer()
                    if !scan.capabilities.profile.displayName.isEmpty {
                        Text(verbatim: scan.capabilities.profile.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(scan.mode.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation = support.explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundColor(support.isUsable ? AppPalette.warning : AppPalette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Rate / dwell

    @ViewBuilder
    private var rateCard: some View {
        if scan.mode != .active {
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    SectionLabel(text: "Dwell per channel")
                    HStack(spacing: DesignToken.Spacing.large) {
                        Slider(
                            value: $scan.dwellMilliseconds,
                            in: Double(ScanChannelPlanner.minimumDwellMilliseconds)...500,
                            step: 10
                        ) {
                            Text("Dwell")
                        }
                        Text("\(Int(scan.dwellMilliseconds)) ms")
                            .font(.caption.monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                    }
                    Text(
                        "One beacon interval is 102.4 ms. Longer dwell catches every access point but makes the sweep slower."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Channel plan

    private var planCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "Channel plan")
                    Spacer()
                    Text(
                        "\(scan.plan.items.count) channels · \(scan.totalDurationLabel)"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                }

                if scan.mode == .directed {
                    HStack(spacing: DesignToken.Spacing.small) {
                        Button("Select 6 GHz") { scan.selectAllDirected(in: .band6) }
                        Button("Select 5 GHz") { scan.selectAllDirected(in: .band5) }
                        Button("Clear") { scan.clearDirected() }
                        Spacer()
                        Text("\(scan.directedSelection.count) selected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .controlSize(.small)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                        ForEach(scan.plan.bands, id: \.self) { band in
                            VStack(alignment: .leading, spacing: DesignToken.Spacing.tight) {
                                SectionLabel(text: band.label)
                                LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 6) {
                                    ForEach(
                                        scan.plan.items.filter { $0.band == band }
                                    ) { item in
                                        channelChip(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.trailing, DesignToken.Spacing.tight)
                }
                .frame(maxHeight: 190)

                ForEach(scan.plan.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func channelChip(_ item: ScanChannelPlanItem) -> some View {
        let isSelectable = scan.mode == .directed
        let isSelected = scan.directedSelection.contains(item.id)
        let tint = AppPalette.band(item.band)
        return Button {
            if isSelectable { scan.toggleDirected(item) }
        } label: {
            VStack(spacing: 1) {
                Text(verbatim: "\(item.channel)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                if let label = item.regulatoryLabel {
                    Text(verbatim: label)
                        .font(.system(size: 8))
                        .foregroundColor(isSelected ? tint : .secondary)
                        .lineLimit(1)
                } else if item.isNeighborReported {
                    Text(verbatim: "RNR")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 60, height: 34)
            .background(
                RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                    .fill(isSelected ? tint.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                    .stroke(
                        isSelected ? tint.opacity(0.6) : Color.secondary.opacity(0.18),
                        lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable || scan.isRunning)
        .help(
            "\(item.channelLabel)\(item.regulatoryLabel.map { " · \($0)" } ?? "")"
                + (item.isNeighborReported ? " · advertised in a Reduced Neighbor Report" : "")
        )
        .accessibilityLabel(item.channelLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressCard: some View {
        if let progress = scan.progress, scan.isRunning || progress.phase != .preparing {
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    HStack {
                        SectionLabel(text: "Progress")
                        Spacer()
                        Text(progress.label)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: progress.fraction)
                    if scan.isRunning {
                        HStack(spacing: DesignToken.Spacing.small) {
                            Button(scan.isCancelling ? "Finishing capture…" : "Cancel") {
                                scan.cancel()
                            }
                            .controlSize(.small)
                            .disabled(scan.isCancelling)
                            Text(
                                "The monitor capture ends with its timer, then the frames are read."
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            if let error = scan.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary = scan.lastSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(scan.lastNotes, id: \.self) { note in
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DesignToken.Spacing.medium) {
                if scan.mode == .active {
                    Text(
                        "Active mode is the analyzer's normal background scan; nothing else to start."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Button(scan.isRunning ? "Listening…" : "Start passive scan") {
                        scan.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!scan.canStart)
                    Text(
                        "Capture needs one administrator authorization, like the Capture tab. Nothing is installed."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
}
