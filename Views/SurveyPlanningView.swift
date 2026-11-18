import SwiftUI

/// P1.4: plan AP placement before walking, then track how much of the plan the
/// active survey has actually covered.
struct SurveyPlanningView: View {
    @ObservedObject var survey: SurveyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab = "plan"
    @State private var widthText = "20"
    @State private var heightText = "12"
    @State private var targetRSSI = -65.0
    @State private var band = "5GHz"
    @State private var channel = 36
    @State private var result: SurveyPlanResult?

    private var request: SurveyPlanRequest {
        SurveyPlanRequest(
            widthMeters: Double(widthText.replacingOccurrences(of: ",", with: ".")) ?? 20,
            heightMeters: Double(heightText.replacingOccurrences(of: ",", with: ".")) ?? 12,
            targetRSSI: Int(targetRSSI), txPowerDbm: 20, band: band, channel: channel
        )
    }

    private var progress: ActiveSurveyProgress {
        ActiveSurveyAdvisor.evaluate(project: survey.project, targetRSSI: Int(targetRSSI))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
            AppSheetHeader(
                icon: "square.grid.3x3.topleft.filled",
                title: "Survey planning",
                subtitle:
                    "Size the space, choose a target, get an AP layout, then track the active walk-through."
            ) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            AppTabBar(
                sections: [
                    AppTabBar.Section(
                        id: "planning",
                        title: nil,
                        items: [
                            .init(id: "plan", title: "Plan", icon: "ruler"),
                            .init(
                                id: "active", title: "Active survey",
                                icon: "figure.walk"),
                        ])
                ],
                selection: $tab,
                showsGroupTitles: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if tab == "plan" {
                planContent
            } else {
                activeContent
            }
        }
        .appSheet(width: 780, minHeight: 540)
        .onAppear {
            widthText = String(format: "%.0f", survey.project.planWidthMeters ?? 20)
            heightText = String(format: "%.0f", survey.project.planHeightMeters ?? 12)
        }
    }

    private var planContent: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.large) {
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                    SectionLabel(text: "Space")
                    Grid(
                        alignment: .leading, horizontalSpacing: DesignToken.Spacing.small,
                        verticalSpacing: DesignToken.Spacing.small
                    ) {
                        GridRow {
                            fieldLabel("Width (m)")
                            TextField("20", text: $widthText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: DesignToken.Layout.controlWidthSmall)
                        }
                        GridRow {
                            fieldLabel("Height (m)")
                            TextField("12", text: $heightText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: DesignToken.Layout.controlWidthSmall)
                        }
                        GridRow {
                            fieldLabel("Target RSSI")
                            HStack(spacing: DesignToken.Spacing.small) {
                                Slider(value: $targetRSSI, in: -80 ... -50, step: 1)
                                    .frame(width: 150)
                                Text("\(Int(targetRSSI)) dBm")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        GridRow {
                            fieldLabel("Band")
                            Picker("Band", selection: $band) {
                                Text("2.4 GHz").tag("2.4GHz")
                                Text("5 GHz").tag("5GHz")
                                Text("6 GHz").tag("6GHz")
                            }
                            .labelsHidden()
                            .frame(width: DesignToken.Layout.controlWidthSmall + 40)
                        }
                        GridRow {
                            fieldLabel("Channel")
                            TextField("36", value: $channel, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: DesignToken.Layout.controlWidthSmall)
                        }
                    }
                    Button {
                        result = SurveyPlanner.plan(request)
                    } label: {
                        Label("Suggest AP layout", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 320)

            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    SectionLabel(text: "Prediction")
                    if let result {
                        HStack(spacing: DesignToken.Spacing.large) {
                            StatTile(value: "\(result.accessPointCount)", label: "Access points")
                            StatTile(
                                value: String(format: "%.0f%%", result.estimatedCoveragePercent),
                                label: "Coverage",
                                tint: result.estimatedCoveragePercent >= 90
                                    ? AppPalette.ok : AppPalette.warning)
                            StatTile(
                                value: String(format: "%.1f m", result.radiusMeters),
                                label: "Radius")
                        }
                        ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            survey.applyPlannedAccessPoints(
                                result.accessPoints, band: band, channel: channel)
                            dismiss()
                        } label: {
                            Label(
                                "Place \(result.accessPointCount) APs on the plan",
                                systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text(
                            "Run the planner to see the suggested number and positions of access points for this floor."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var activeContent: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.large) {
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                    SectionLabel(text: "Coverage of the walk-through")
                    HStack(spacing: DesignToken.Spacing.large) {
                        StatTile(
                            value: "\(progress.collectedSamples)",
                            label: "Samples of \(progress.requiredSamples)")
                        StatTile(
                            value: String(format: "%.0f%%", progress.coveragePercent),
                            label: "Cells covered",
                            tint: progress.coveragePercent >= 90
                                ? AppPalette.ok : AppPalette.warning)
                        StatTile(
                            value: progress.averageRSSI.map { "\($0) dBm" } ?? "—",
                            label: "Average")
                        StatTile(
                            value: progress.weakestRSSI.map { "\($0) dBm" } ?? "—",
                            label: "Weakest", tint: AppPalette.warning)
                    }
                    ProgressView(
                        value: progress.coveragePercent, total: 100
                    )
                    .progressViewStyle(.linear)
                    if progress.gaps.isEmpty {
                        Label(
                            "Every cell has at least one sample. Export the report.",
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.caption)
                        .foregroundColor(AppPalette.ok)
                    } else {
                        Text(
                            "\(progress.gaps.count) cells still have no sample. Take the next one near the highlighted target."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    SectionLabel(text: "Next target")
                    if let target = progress.nextTarget {
                        let width = survey.project.planWidthMeters ?? 20
                        let height = survey.project.planHeightMeters ?? 12
                        Text(
                            String(
                                format: String(localized: "%.1f m from the left wall, %.1f m from the top"),
                                target.x * width, target.y * height)
                        )
                        .font(.callout.monospacedDigit())
                        Text(
                            "Click that spot on the plan in Survey mode to record the next sample."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No gaps left for this floor.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    Text(
                        "Targets follow a \(3) m grid over the current plan. Walls and AP placement are already applied to the heatmap."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(width: 84, alignment: .leading)
    }
}
