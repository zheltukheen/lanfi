import LanFiCore
import SwiftUI
import AppKit

struct SurveyView: View {
    @ObservedObject var analyzer: AnalyzerViewModel
    @ObservedObject var survey: SurveyViewModel
    @State private var mode: SurveyToolMode = .sample
    @State private var pendingWallStart: CGPoint?
    @State private var wallMaterial: SurveyWallMaterial = .drywall
    @State private var antennaPattern: SurveyAntennaPattern = .omni
    @State private var antennaHeading = 0.0
    @State private var useCalibration = true
    @State private var roomPoints: [SurveyPoint] = []
    @State private var cutoutPoints: [SurveyPoint] = []
    @State private var lastWalkSample = Date.distantPast
    @State private var showReportSettings = false
    @AppStorage(AppSettingsKey.surveyHeatmapDetail.rawValue) private var heatmapDetail = "balanced"
    @State private var show3DFloors = false
    @State private var calibrationPoints: [SurveyPoint] = []
    @State private var showingClearConfirm = false
    @State private var showingBlankPlan = false
    @State private var showingPlanning = false
    @State private var showingMap = false
    @State private var heatGrid: HeatGridCache.Grid?
    /// Pan and zoom of the plan view. The heat grid is still built for the
    /// fitted sheet; these only transform what is drawn, so sampling and the
    /// overlay geometry keep working in plan coordinates.
    @State private var planZoom: CGFloat = 1
    @State private var planPan: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?

    private var selectedNetwork: NetworkModel? {
        guard let id = survey.selectedNetworkId else { return nil }
        return analyzer.networks.first { $0.id == id }
    }

    private var captureNetwork: NetworkModel? {
        selectedNetwork ?? analyzer.networks.max { $0.signal < $1.signal }
    }

    private var displayedSamples: [SurveySample] {
        survey.samples(for: selectedNetwork)
    }

    private var calibration: SurveyCalibration? {
        SurveyCalibrationCalculator.compute(project: survey.project)
    }

    private var calibrationOffset: Double {
        useCalibration ? (calibration?.offsetDb ?? 0) : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                surveyInspector
                    .frame(width: 268)
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showReportSettings) {
            SurveyReportSettingsView(survey: survey)
        }
        .sheet(isPresented: $show3DFloors) {
            MultiFloorSurveyView(survey: survey)
        }
        .sheet(isPresented: $showingBlankPlan) {
            BlankPlanSheet(survey: survey)
        }
        .sheet(isPresented: $showingPlanning) {
            SurveyPlanningView(survey: survey)
        }
        .sheet(isPresented: $showingMap) {
            SurveyMapSheet(survey: survey)
        }
        .alert("Clear all survey points?", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Points", role: .destructive) { survey.clearSamples() }
        } message: {
            Text("Walls, rooms and predictive access points stay in place.")
        }
    }

    /// One compact strip. The screen used to stack two rows of toolbars under
    /// the tool header, which cost a third of the window before the plan even
    /// started; the actions that do not belong in a header live in two menus.
    private var header: some View {
        ToolkitHeaderBar {
            HStack(spacing: DesignToken.Spacing.small) {
                Picker(
                    String(localized: "Floor"),
                    selection: Binding(
                        get: { survey.project.id },
                        set: { survey.selectProject(id: $0) }
                    )
                ) {
                    ForEach(survey.projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .frame(width: 150)
                .controlSize(.small)

                ToolbarIconButton(
                    systemImage: "plus.rectangle.on.rectangle", label: "New floor",
                    help: "New floor"
                ) { survey.newFloor() }

                ToolbarIconButton(
                    systemImage: "square.3.layers.3d", label: "Multi-floor 3D view",
                    help: "Multi-floor 3D view"
                ) { show3DFloors = true }

                Divider().frame(height: 18)

                ToolbarIconButton(
                    systemImage: "square.grid.3x3.topleft.filled", label: "Plan",
                    help: "Plan AP placement and track the active survey"
                ) { showingPlanning = true }

                ToolbarIconButton(
                    systemImage: "map", label: "Map",
                    help: "GPS-tagged samples and GPX tracks"
                ) { showingMap = true }

                Divider().frame(height: 18)

                networkMenu

                if let selectedNetwork {
                    Text(
                        "\(selectedNetwork.signal) dBm · \(selectedNetwork.bandLabel) · ch \(selectedNetwork.channel)"
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
        } trailing: {
            HStack(spacing: DesignToken.Spacing.small) {
                fileMenu
                overflowMenu
            }
        }
    }

    private var networkMenu: some View {
        Menu {
            Button(String(localized: "All networks")) { survey.selectedNetworkId = nil }
            ForEach(analyzer.networks.sorted { $0.signal > $1.signal }) { network in
                Button("\(network.displaySSID) · \(network.bssid)") {
                    survey.selectedNetworkId = network.id
                }
            }
        } label: {
            AppMenuLabel(
                title: selectedNetwork?.displaySSID ?? String(localized: "All networks"),
                systemImage: "wifi",
                isActive: selectedNetwork != nil)
        }
        .appMenuStyle()
        .help("Network")
        .accessibilityLabel("Network")
    }

    private var fileMenu: some View {
        Menu {
            Button(String(localized: "Import Floor Plan"), systemImage: "photo") {
                survey.importFloorPlan()
            }
            Button(String(localized: "New Plan"), systemImage: "square.dashed") {
                showingBlankPlan = true
            }
            Button(String(localized: "Save"), systemImage: "square.and.arrow.down") {
                survey.save()
            }
            Divider()
            Menu(String(localized: "PDF")) {
                Button(String(localized: "This floor")) {
                    survey.exportPDF(
                        networkName: selectedNetwork?.displaySSID ?? "All networks",
                        samples: displayedSamples)
                }
                Button(String(localized: "All floors")) {
                    survey.exportAllFloorsPDF(
                        networkName: selectedNetwork?.displaySSID ?? "All networks")
                }
            }
            Button(String(localized: "Report"), systemImage: "doc.badge.gearshape") {
                showReportSettings = true
            }
            Divider()
            Button(String(localized: "Clear Points"), role: .destructive) {
                survey.clearSamples()
            }
            .disabled(survey.samples.isEmpty)
        } label: {
            AppIconMenuLabel(systemImage: "folder")
        }
        .appMenuStyle()
        .help("Plan file")
        .accessibilityLabel("Plan file")
    }

    private var overflowMenu: some View {
        Menu {
            Picker(String(localized: "Heatmap detail"), selection: $heatmapDetail) {
                Text("Fast").tag("fast")
                Text("Balanced").tag("balanced")
                Text("High").tag("high")
            }
            Divider()
            Button(String(localized: "Draw Room"), systemImage: "rectangle.dashed") {
                select(.room)
            }
            .disabled(mode == .room)
            Button(String(localized: "Finish Room")) { finishRoom() }
                .disabled(roomPoints.count < 3)
            Button(String(localized: "Clear Rooms"), role: .destructive) {
                survey.clearObstacles()
                roomPoints = []
            }
            .disabled(survey.obstacles.isEmpty)
            Button(String(localized: "Finish Cutout")) { finishCutout() }
                .disabled(cutoutPoints.count < 3)
            Button(String(localized: "Clear Cutouts"), role: .destructive) {
                survey.clearCutouts()
                cutoutPoints = []
            }
            .disabled(survey.cutouts.isEmpty)
            Button(String(localized: "Clear Predictive APs"), role: .destructive) {
                survey.clearAccessPoints()
            }
            .disabled(survey.accessPoints.isEmpty)
            Divider()
            Button(
                mode == .calibrate
                    ? String(localized: "Cancel Calibration")
                    : String(localized: "Calibrate Scale")
            ) {
                if mode == .calibrate {
                    select(.sample)
                } else {
                    select(.calibrate)
                }
            }
            Picker(String(localized: "Wall material"), selection: $wallMaterial) {
                ForEach(SurveyWallMaterial.allCases) { material in
                    Text("\(material.title) · \(Int(material.attenuationDb)) dB").tag(material)
                }
            }
            Picker(String(localized: "Antenna"), selection: $antennaPattern) {
                ForEach(SurveyAntennaPattern.allCases) { pattern in
                    Text(pattern.title).tag(pattern)
                }
            }
            Picker(String(localized: "Heading"), selection: $antennaHeading) {
                ForEach(Array(stride(from: 0.0, to: 360.0, by: 45.0)), id: \.self) { heading in
                    Text(headingLabel(heading)).tag(heading)
                }
            }
            .disabled(antennaPattern == .omni)
            Button(String(localized: "Apply antenna to all APs")) {
                survey.setAntennaForAllAccessPoints(
                    pattern: antennaPattern, headingDegrees: antennaHeading)
            }
            .disabled(survey.accessPoints.isEmpty)
            Toggle(String(localized: "Calibrate from samples"), isOn: $useCalibration)
                .disabled(calibration == nil)
            Button(String(localized: "Clear Walls"), role: .destructive) {
                survey.clearWalls()
                pendingWallStart = nil
            }
            .disabled(survey.walls.isEmpty)
        } label: {
            AppIconMenuLabel(systemImage: "ellipsis.circle")
        }
        .appMenuStyle()
        .help("Structure")
        .accessibilityLabel("More tools")
    }

    // MARK: - Inspector

    private var surveyInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                metricsCard
                validationCard
                toolCard
                networkCard
                if survey.hasPlan {
                    samplesCard
                }
                tipsCard
            }
            .padding(DesignToken.Spacing.medium)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private var headerCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "map")
                        .foregroundColor(.accentColor)
                    Text(survey.project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                Text(
                    String(
                        format: String(localized: "Floor %lld · %lld points"),
                        survey.project.floorLevel + 1, survey.project.samples.count)
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                Text(survey.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metricsCard: some View {
        let samples = displayedSamples
        let average =
            samples.isEmpty
            ? nil : samples.map(\.rssi).reduce(0, +) / samples.count
        let best = samples.map(\.rssi).max()
        return ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Coverage")
                HStack(spacing: 12) {
                    ToolkitMetric(title: "Points", value: "\(samples.count)")
                    ToolkitMetric(
                        title: "Average",
                        value: average.map { "\($0) dBm" } ?? "—",
                        tint: average.map { $0 >= -65 ? Color.green : .orange } ?? .primary)
                    ToolkitMetric(
                        title: "Best", value: best.map { "\($0) dBm" } ?? "—",
                        tint: best.map { $0 >= -55 ? Color.green : .primary } ?? .primary)
                }
                HStack(spacing: 12) {
                    ToolkitMetric(title: "Walls", value: "\(survey.walls.count)")
                    ToolkitMetric(title: "Rooms", value: "\(survey.obstacles.count)")
                    ToolkitMetric(title: "APs", value: "\(survey.accessPoints.count)")
                }
                if let calibration, useCalibration {
                    Text(calibration.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// G9: the requirement is off until chosen, and the verdict is computed
    /// from the same samples the heatmap draws.
    private var validationCard: some View {
        let requirement = survey.requirement
        let report = SurveyValidator.evaluate(
            samples: displayedSamples, requirement: requirement)
        return ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                ToolkitSectionLabel(text: "Pass/fail")
                Toggle(
                    "Validate against requirement",
                    isOn: Binding(
                        get: { survey.requirement.isEnabled },
                        set: { enabled in
                            var updated = survey.requirement
                            updated.isEnabled = enabled
                            survey.updateRequirement(updated)
                        })
                )
                .font(.caption2)
                .toggleStyle(.switch)
                .controlSize(.mini)

                if requirement.isEnabled {
                    Stepper(
                        value: requirementBinding(\.minRSSI),
                        in: (-90)...(-40)
                    ) {
                        Text("Min RSSI \(requirement.minRSSI) dBm")
                            .font(.caption2.monospacedDigit())
                    }
                    Toggle(
                        "Check throughput",
                        isOn: Binding(
                            get: { survey.requirement.judgesThroughput },
                            set: { enabled in
                                var updated = survey.requirement
                                updated.minThroughputMbps = enabled ? 50 : nil
                                survey.updateRequirement(updated)
                            })
                    )
                    .font(.caption2)
                    if requirement.judgesThroughput {
                        Stepper(
                            value: Binding(
                                get: { survey.requirement.minThroughputMbps ?? 50 },
                                set: { value in
                                    var updated = survey.requirement
                                    updated.minThroughputMbps = value
                                    survey.updateRequirement(updated)
                                }),
                            in: 5...500, step: 5
                        ) {
                            Text("Min \(Int(requirement.minThroughputMbps ?? 50)) Mbps")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    Toggle(
                        "Check latency",
                        isOn: Binding(
                            get: { survey.requirement.judgesLatency },
                            set: { enabled in
                                var updated = survey.requirement
                                updated.maxLatencyMilliseconds = enabled ? 100 : nil
                                survey.updateRequirement(updated)
                            })
                    )
                    .font(.caption2)
                    if requirement.judgesLatency {
                        Stepper(
                            value: Binding(
                                get: { survey.requirement.maxLatencyMilliseconds ?? 100 },
                                set: { value in
                                    var updated = survey.requirement
                                    updated.maxLatencyMilliseconds = value
                                    survey.updateRequirement(updated)
                                }),
                            in: 10...300, step: 10
                        ) {
                            Text("Max \(Int(requirement.maxLatencyMilliseconds ?? 100)) ms")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    Text(requirement.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    if let report {
                        Text(report.verdict)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(report.isPassing ? .green : .orange)
                        if let worst = report.worstRegion {
                            Text("Worst: \(worst)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        let unmeasured = max(
                            report.unmeasuredThroughput, report.unmeasuredLatency)
                        if unmeasured > 0 {
                            Text(
                                "\(unmeasured) points have no throughput/latency measurement and are not judged on it."
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("Record points to see a verdict.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(
                        "Off by default. Turn it on to judge sampled points against your own thresholds; the PDF and HTML report then carry the verdict."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func requirementBinding(_ keyPath: WritableKeyPath<SurveyRequirement, Int>)
        -> Binding<Int>
    {
        Binding(
            get: { survey.requirement[keyPath: keyPath] },
            set: { value in
                var updated = survey.requirement
                updated[keyPath: keyPath] = value
                survey.updateRequirement(updated)
            })
    }

    private func drawFailureRing(
        context: GraphicsContext, rect: CGRect, failure: SurveyValidationReport.Failure
    ) {
        let point = CGPoint(
            x: rect.minX + failure.x * rect.width,
            y: rect.minY + failure.y * rect.height)
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)),
            with: .color(.red), lineWidth: 2)
    }

    private var toolCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                ToolkitSectionLabel(text: "Plan tool")
                // Every tool is one visible click: the toolbar only had three
                // icon toggles and a menu, and the pattern of which click did
                // what was impossible to guess.
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(SurveyToolMode.allCases) { tool in
                        toolChip(tool)
                    }
                }
                Text(currentToolHint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toolChip(_ tool: SurveyToolMode) -> some View {
        let selected = mode == tool
        return Button {
            select(tool)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tool.icon)
                    .font(.caption2)
                Text(tool.shortTitle)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(selected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(selected ? currentTint(for: tool) : Theme.Surface.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .stroke(Theme.Surface.border, lineWidth: selected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(tool.hint)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func currentTint(for tool: SurveyToolMode) -> Color {
        switch tool.tone {
        case .accent: return .accentColor
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .cyan: return .cyan
        }
    }

    private var networkCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                ToolkitSectionLabel(text: "Capture")
                if let network = captureNetwork {
                    Text(network.displaySSID)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("\(network.signal) dBm · \(network.bandLabel) · ch \(network.channel)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                    Text(selectedNetwork == nil ? "Strongest visible network" : "Selected network")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("No Wi-Fi networks visible. Start a scan in the Wi-Fi Analyzer.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func headingLabel(_ degrees: Double) -> String {
        let directions = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
        let index = Int((degrees / 45).rounded()) % directions.count
        return "\(Int(degrees))° \(directions[index])"
    }

    private func measurementLabel(_ sample: SurveySample) -> String {
        let down = sample.downloadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—"
        let latency = sample.latencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—"
        return "\(down) · \(latency)"
    }

    private var samplesCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ToolkitSectionLabel(text: "Points")
                    Spacer()
                    Button(survey.isMeasuringPoint ? "Measuring…" : "Measure") {
                        survey.measureLastSample()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .disabled(survey.samples.isEmpty || survey.isMeasuringPoint)
                    .help("Run a speed test at the newest point")
                    Button("Undo") { survey.removeLastSample() }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .disabled(survey.samples.isEmpty)
                }
                if displayedSamples.isEmpty {
                    Text("Click the plan to add the first point.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(displayedSamples.suffix(14).reversed())) { sample in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(heatColor(sample.rssi))
                                .frame(width: 7, height: 7)
                            Text("\(sample.rssi) dBm")
                                .font(.caption2.monospacedDigit())
                                .frame(width: 52, alignment: .leading)
                            Text(sample.ssid)
                                .font(.caption2)
                                .lineLimit(1)
                            if sample.downloadMbps != nil || sample.latencyMilliseconds != nil {
                                Text(measurementLabel(sample))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                survey.removeSample(id: sample.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                            .buttonStyle(.borderless)
                            .help("Remove point")
                            .accessibilityLabel("Remove survey point")
                        }
                    }
                }
                Divider()
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("Clear all points", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(survey.samples.isEmpty)
            }
        }
    }

    private var tipsCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                ToolkitSectionLabel(text: "How to survey")
                tipRow("1", "Import a floor plan or create a blank metre grid.")
                tipRow("2", "Walk the area and click to record RSSI.")
                tipRow("3", "Add walls and rooms for realistic attenuation.")
                tipRow("4", "Export a PDF report or inspect the 3D view.")
            }
        }
    }

    private func tipRow(_ number: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(number)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .frame(width: 15, height: 15)
                .background(DesignToken.Surface.selectionFill, in: Circle())
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentToolTitle: String { mode.title }

    private var currentToolIcon: String { mode.icon }

    private var currentToolTint: Color { currentTint(for: mode) }

    private var currentToolHint: String { mode.hint }

    /// Switching tools clears the half-finished geometry of the previous one, so
    /// a half-drawn wall cannot surprise the next click in another mode.
    private func select(_ newMode: SurveyToolMode) {
        mode = newMode
        if newMode != .calibrate { calibrationPoints = [] }
        if newMode != .room { roomPoints = [] }
        if newMode != .cutout { cutoutPoints = [] }
        if newMode != .wall { pendingWallStart = nil }
        survey.statusMessage = newMode.activationMessage
    }

    @ViewBuilder
    private var content: some View {
        if !survey.hasPlan {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.accentColor.opacity(0.75))
                    Text("Start a site survey")
                        .font(.title2.bold())
                    Text(
                        "Import a floor plan, record signal strength around the space, and see a continuous coverage heatmap."
                    )
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                    HStack(alignment: .top, spacing: 12) {
                        onboardingStep(
                            icon: "photo", title: "1 · Floor plan",
                            detail: "Import a PNG/JPEG, or create a blank metre grid and draw walls by hand.")
                        onboardingStep(
                            icon: "hand.tap", title: "2 · Record",
                            detail: "Click on the plan or use Walk mode to sample the selected network.")
                        onboardingStep(
                            icon: "square.3.layers.3d", title: "3 · Analyse",
                            detail: "Add walls and rooms, place predictive APs and export a PDF.")
                    }
                    .frame(maxWidth: 760)

                    HStack(spacing: 10) {
                        Button {
                            survey.importFloorPlan()
                        } label: {
                            Label("Import Floor Plan", systemImage: "photo")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button {
                            showingBlankPlan = true
                        } label: {
                            Label("New Blank Plan", systemImage: "square.dashed")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        Button {
                            survey.newFloor()
                        } label: {
                            Label("New Floor", systemImage: "plus.rectangle.on.rectangle")
                        }
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(DesignToken.Layout.emptyStatePadding)
            }
        } else {
            GeometryReader { geo in
                // The sheet is the drawable area. Everything below — grid,
                // heat, overlays, gesture — uses its own local frame, so a
                // click can never be off by the letterbox offset and the
                // overlays can never leave the plan.
                let rect = fittedRect(in: geo.size)
                let sheet = CGRect(origin: .zero, size: rect.size)
                let cell: CGFloat =
                    heatmapDetail == "fast" ? 8 : (heatmapDetail == "high" ? 4 : 6)
                let columns = max(1, Int(sheet.width / cell))
                let rows = max(1, Int(sheet.height / cell))
                let planWidthMeters = survey.project.planWidthMeters ?? 12
                let planHeightMeters = resolvedPlanHeightMeters
                let request = SurveyHeatmapRequest(
                    columns: columns, rows: rows, cellSize: Double(cell),
                    pixelWidth: Double(sheet.width), pixelHeight: Double(sheet.height),
                    samples: displayedSamples, walls: survey.walls,
                    obstacles: survey.obstacles, accessPoints: survey.accessPoints,
                    predictiveMode: mode == .predictive,
                    // Must match `fittedRect` and `drawPlanGrid`, or the
                    // predicted coverage is drawn at the wrong scale.
                    planWidthMeters: planWidthMeters,
                    planHeightMeters: planHeightMeters,
                    calibrationDb: calibrationOffset,
                    cutouts: survey.project.cutouts
                )
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    ZStack(alignment: .topLeading) {
                        if let image = survey.floorPlanImage {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: sheet.width, height: sheet.height)
                                .clipped()
                        }
                        Canvas { context, _ in
                            if survey.floorPlanImage == nil {
                                drawPlanGrid(context: context, rect: sheet)
                            }
                            if let heatGrid {
                                drawHeatGrid(context: context, rect: sheet, grid: heatGrid, cell: cell)
                            }
                            for sample in displayedSamples {
                                let point = CGPoint(
                                    x: sheet.minX + sample.x * sheet.width,
                                    y: sheet.minY + sample.y * sheet.height
                                )
                                drawSample(context: context, at: point, rssi: sample.rssi)
                            }
                            if survey.requirement.isEnabled,
                                let validation = SurveyValidator.evaluate(
                                    samples: displayedSamples,
                                    requirement: survey.requirement)
                            {
                                for failure in validation.failures {
                                    drawFailureRing(
                                        context: context, rect: sheet, failure: failure)
                                }
                            }
                            drawWalls(context: context, rect: sheet)
                            drawRooms(context: context, rect: sheet)
                            drawCutouts(context: context, rect: sheet)
                            drawAccessPoints(context: context, rect: sheet)
                            drawCalibration(context: context, rect: sheet)
                        }
                        .allowsHitTesting(false)
                        .task(id: request.key) {
                            // Build the grid once per request key on a background
                            // task. The previous streaming loop restarted on every
                            // key change and could end up publishing nothing, which
                            // left the plan without any heat at all.
                            heatGrid = nil
                            let built = await Task.detached(priority: .userInitiated) {
                                request.build()
                            }.value
                            guard !Task.isCancelled else { return }
                            heatGrid = built
                        }
                        .accessibilityLabel(String(localized: "Floor plan heatmap"))
                        .accessibilityValue(
                            String(
                                format: String(localized: "%lld samples, %lld walls, %@"),
                                displayedSamples.count, survey.walls.count,
                                selectedNetwork?.displaySSID ?? String(localized: "all networks")))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedNetwork?.displaySSID ?? "All networks")
                                .font(.caption.bold())
                            Text(
                                "\(displayedSamples.count) points · \(survey.walls.count) walls · \(survey.obstacles.count) rooms"
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            Text(survey.statusMessage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: 260, alignment: .leading)
                            if heatGrid == nil,
                                !displayedSamples.isEmpty
                                    || (mode == .predictive && !survey.accessPoints.isEmpty)
                            {
                                Text("Computing coverage…")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(DesignToken.Spacing.small)
                        .appCardSurface(radius: Theme.Radius.control)
                        .padding(DesignToken.Spacing.small)

                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                legend
                            }
                        }
                        .padding(DesignToken.Spacing.small)

                        if displayedSamples.isEmpty, mode != .predictive {
                            VStack(spacing: 5) {
                                Image(systemName: mode.icon)
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                Text(mode.hint)
                                    .font(.caption.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 260)
                                Text(
                                    captureNetwork?.displaySSID
                                        ?? String(localized: "Start a Wi-Fi scan first")
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, DesignToken.Spacing.large)
                            .padding(.vertical, DesignToken.Spacing.medium)
                            .appCardSurface()
                            .position(x: sheet.midX, y: sheet.midY)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(width: sheet.width, height: sheet.height)
                    .scaleEffect(planZoom, anchor: .center)
                    .offset(planPan)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // A drag pans the plan instead of doing
                                // nothing: before this, the gesture swallowed
                                // every drag and the map could not be moved.
                                if panStart == nil { panStart = planPan }
                                let base = panStart ?? .zero
                                planPan = clampPlanPan(
                                    CGSize(
                                        width: base.width
                                            + value.translation.width * planZoom,
                                        height: base.height
                                            + value.translation.height * planZoom),
                                    size: geo.size, sheet: sheet)
                            }
                            .onEnded { value in
                                panStart = nil
                                guard abs(value.translation.width) < 4,
                                    abs(value.translation.height) < 4
                                else { return }
                                surveyTap(
                                    at: CGPoint(
                                        x: min(max(value.location.x, 0), sheet.width),
                                        y: min(max(value.location.y, 0), sheet.height)),
                                    in: sheet)
                            }
                    )
                    .onContinuousHover { phase in
                        guard mode == .walk, phase != .ended else { return }
                        guard case .active(let location) = phase else { return }
                        guard sheet.width > 0, sheet.height > 0 else { return }
                        let now = Date()
                        guard now.timeIntervalSince(lastWalkSample) >= 0.8 else { return }
                        guard let network = captureNetwork else { return }
                        lastWalkSample = now
                        survey.addSample(
                            x: Double(location.x / sheet.width),
                            y: Double(location.y / sheet.height),
                            network: network
                        )
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let base = zoomStart ?? planZoom
                                if zoomStart == nil { zoomStart = planZoom }
                                planZoom = min(max(base * value, 0.6), 6)
                                panStart = nil
                            }
                            .onEnded { _ in zoomStart = nil }
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    planZoomControls()
                        .padding(DesignToken.Spacing.small)
                }
                .clipped()
            }
        }
    }

    /// Zoom buttons, so the plan can be navigated without a trackpad pinch and
    /// always has a way back to the fitted view.
    private func planZoomControls() -> some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            AppIconButton(systemImage: "minus.magnifyingglass", label: "Zoom out") {
                planZoom = max(0.6, planZoom / 1.25)
                if planZoom <= 1 { planPan = .zero }
            }
            Text(verbatim: "\(Int(planZoom * 100))%")
                .font(.caption2.monospacedDigit())
                .frame(width: 38)
            AppIconButton(systemImage: "plus.magnifyingglass", label: "Zoom in") {
                planZoom = min(6, planZoom * 1.25)
            }
            AppIconButton(systemImage: "arrow.counterclockwise", label: "Reset view") {
                planZoom = 1
                planPan = .zero
            }
            .disabled(planZoom == 1 && planPan == .zero)
        }
        .padding(.horizontal, DesignToken.Spacing.small)
        .appCardSurface(radius: Theme.Radius.control)
        .help("Drag the plan to move it; pinch or use these buttons to zoom")
    }

    /// Keeps the drawn sheet reachable: at 1× the plan already fits and does
    /// not move, above that the pan stops at the plan's own edges.
    private func clampPlanPan(_ pan: CGSize, size: CGSize, sheet: CGRect) -> CGSize {
        let limitX = max(0, (sheet.width * planZoom - size.width) / 2)
        let limitY = max(0, (sheet.height * planZoom - size.height) / 2)
        return CGSize(
            width: min(max(pan.width, -limitX), limitX),
            height: min(max(pan.height, -limitY), limitY))
    }

    /// Records a tap on the plan. `SpatialTapGesture` is the supported way to
    /// get the click position; the location closure of `onTapGesture` stopped
    /// arriving on current macOS, which left the plan unclickable and the
    /// heatmap without any samples.
    private func surveyTap(at location: CGPoint, in rect: CGRect) {
        guard rect.contains(location), rect.width > 0, rect.height > 0 else { return }
        let x = Double((location.x - rect.minX) / rect.width)
        let y = Double((location.y - rect.minY) / rect.height)
        if mode == .calibrate {
            calibrationPoints.append(SurveyPoint(x: x, y: y))
            if calibrationPoints.count == 2 {
                finishCalibration()
            }
            return
        }
        if mode == .predictive {
            let network = captureNetwork
            survey.addAccessPoint(
                x: x, y: y,
                band: network?.band.label ?? "5GHz",
                channel: network?.channel ?? 36,
                pattern: antennaPattern, headingDegrees: antennaHeading
            )
            return
        }
        if mode == .cutout {
            cutoutPoints.append(SurveyPoint(x: x, y: y))
            return
        }
        if mode == .room {
            roomPoints.append(SurveyPoint(x: x, y: y))
            survey.statusMessage = String(
                format: String(localized: "Room vertices: %lld. Finish Room when ready."),
                roomPoints.count)
            return
        }
        if mode == .wall {
            if let start = pendingWallStart {
                survey.addWall(
                    x1: Double(start.x), y1: Double(start.y), x2: x, y2: y,
                    material: wallMaterial)
                pendingWallStart = nil
            } else {
                pendingWallStart = CGPoint(x: x, y: y)
                survey.statusMessage = String(
                    localized: "Wall start set. Click the second point.")
            }
            return
        }
        guard let network = captureNetwork else {
            // A silent no-op here looked like a broken plan: the user clicked
            // and nothing at all happened.
            survey.statusMessage = String(
                localized:
                    "No network captured yet. Start a Wi-Fi scan in the analyzer, then click the plan.")
            return
        }
        survey.addSample(x: x, y: y, network: network)
    }

    private func onboardingStep(
        icon: String, title: LocalizedStringKey, detail: LocalizedStringKey
    ) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func finishCalibration() {
        let first = calibrationPoints[0]
        let second = calibrationPoints[1]
        let distance = hypot(second.x - first.x, second.y - first.y)
        guard distance > 0 else {
            calibrationPoints = []
            return
        }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        field.placeholderString = String(localized: "metres")
        let alert = NSAlert()
        alert.messageText = String(localized: "Calibrate plan scale")
        alert.informativeText = String(
            localized: "Enter the real-world distance between the two points.")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Apply"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn,
            let meters = Double(field.stringValue.replacingOccurrences(of: ",", with: "."))
        {
            survey.calibrateScale(realMeters: meters, normalizedDistance: distance)
        }
        calibrationPoints = []
        mode = .sample
    }

    private func drawCalibration(context: GraphicsContext, rect: CGRect) {
        guard calibrationPoints.count == 2 else {
            if let point = calibrationPoints.first {
                let p = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.cyan))
            }
            return
        }
        let a = calibrationPoints[0]
        let b = calibrationPoints[1]
        let p1 = CGPoint(x: rect.minX + a.x * rect.width, y: rect.minY + a.y * rect.height)
        let p2 = CGPoint(x: rect.minX + b.x * rect.width, y: rect.minY + b.y * rect.height)
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
    }

    private func finishRoom() {
        guard roomPoints.count >= 3 else { return }
        survey.addObstacle(points: roomPoints)
        roomPoints = []
        mode = .sample
    }

    private func finishCutout() {
        guard cutoutPoints.count >= 3 else { return }
        survey.addCutout(points: cutoutPoints)
        cutoutPoints = []
        mode = .sample
    }

    /// Interpolates one grid cell. Predictive mode (placed access points)
    /// takes precedence over measured samples, matching the previous
    /// drawing behaviour.
    private func estimateRSSI(nx: Double, ny: Double) -> Int? {
        guard !survey.project.cutouts.contains(where: { $0.contains(x: nx, y: ny) }) else {
            return nil
        }
        if mode == .predictive && !survey.accessPoints.isEmpty {
            return SurveyPredictor.estimate(
                x: nx, y: ny, accessPoints: survey.accessPoints,
                walls: survey.walls, obstacles: survey.obstacles,
                planWidthMeters: survey.project.planWidthMeters ?? 30,
                planHeightMeters: resolvedPlanHeightMeters,
                calibrationDb: calibrationOffset,
                cutouts: survey.project.cutouts
            )
        }
        guard !displayedSamples.isEmpty else { return nil }
        return SurveyInterpolator.estimate(
            x: nx, y: ny, samples: displayedSamples, walls: survey.walls,
            obstacles: survey.obstacles
        )
    }

    private func drawHeatGrid(
        context: GraphicsContext, rect: CGRect, grid: HeatGridCache.Grid, cell: CGFloat
    ) {
        let predicted = mode == .predictive && !survey.accessPoints.isEmpty
        let baseOpacity = predicted ? 0.42 : 0.46
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                guard let rssi = grid.cells[row * grid.columns + column] else { continue }
                let nx = (CGFloat(column) + 0.5) * cell / max(1, rect.width)
                let ny = (CGFloat(row) + 0.5) * cell / max(1, rect.height)
                // Interpolation has no range limit, so one sample used to paint
                // the whole floor as excellent. Fading the confidence with the
                // distance to the nearest real sample keeps the colour where it
                // was measured and leaves the far corners honest and readable.
                let confidence = predicted ? 1 : heatConfidence(x: Double(nx), y: Double(ny))
                guard confidence > 0.06 else { continue }
                context.fill(
                    Path(
                        CGRect(
                            x: rect.minX + CGFloat(column) * cell,
                            y: rect.minY + CGFloat(row) * cell,
                            width: cell + 0.5, height: cell + 0.5
                        )),
                    with: .color(heatColor(rssi).opacity(baseOpacity * confidence))
                )
            }
        }
    }

    /// 1 next to a sample, falling smoothly to 0 around eight metres away.
    private func heatConfidence(x: Double, y: Double) -> Double {
        let widthMeters = survey.project.planWidthMeters ?? 12
        let heightMeters = resolvedPlanHeightMeters
        var nearest = Double.greatestFiniteMagnitude
        for sample in displayedSamples {
            let dx = (sample.x - x) * widthMeters
            let dy = (sample.y - y) * heightMeters
            nearest = min(nearest, (dx * dx + dy * dy).squareRoot())
        }
        guard nearest.isFinite else { return 0 }
        // Linear falloff with a hard edge: an inverse-square tail kept a faint
        // tint over the whole floor, which read as "everything is covered".
        return max(0, 1 - nearest / 5)
    }

    private func drawAccessPoints(context: GraphicsContext, rect: CGRect) {
        for ap in survey.accessPoints {
            let point = CGPoint(x: rect.minX + ap.x * rect.width, y: rect.minY + ap.y * rect.height)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
                with: .color(.purple)
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
                with: .color(.white.opacity(0.9)),
                lineWidth: 1.5
            )
            context.draw(
                Text("AP").font(.system(size: 8, weight: .bold)).foregroundColor(.white),
                at: CGPoint(x: point.x, y: point.y - 14)
            )
        }
    }

    private func drawRooms(context: GraphicsContext, rect: CGRect) {
        for obstacle in survey.obstacles where obstacle.points.count >= 3 {
            var path = Path()
            for (index, point) in obstacle.points.enumerated() {
                let p = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            context.fill(path, with: .color(.orange.opacity(0.16)))
            context.stroke(path, with: .color(.orange.opacity(0.75)), lineWidth: 1.5)
        }
        if roomPoints.count > 0 {
            var path = Path()
            for (index, point) in roomPoints.enumerated() {
                let p = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(.orange), lineWidth: 2)
            for point in roomPoints {
                let p = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.orange))
            }
        }
    }

    private func drawCutouts(context: GraphicsContext, rect: CGRect) {
        for cutout in survey.cutouts where cutout.points.count >= 3 {
            var path = Path()
            for (index, point) in cutout.points.enumerated() {
                let p = CGPoint(
                    x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            context.fill(path, with: .color(.purple.opacity(0.18)))
            context.stroke(
                path, with: .color(.purple.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }
        if cutoutPoints.count > 0 {
            var path = Path()
            for (index, point) in cutoutPoints.enumerated() {
                let p = CGPoint(
                    x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(.purple), lineWidth: 2)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("-90").font(.caption2).foregroundColor(.secondary)
            LinearGradient(colors: [.red, .orange, .yellow, .green], startPoint: .leading, endPoint: .trailing)
                .frame(width: 110, height: 7)
                .clipShape(Capsule())
            Text("-40 dBm").font(.caption2).foregroundColor(.secondary)
            Text("· walls/rooms -8 dB").font(.caption2).foregroundColor(.secondary)
            if mode == .predictive { Text("· predictive").font(.caption2).foregroundColor(.purple) }
            if survey.requirement.isEnabled {
                Text("· red ring = fails requirement").font(.caption2).foregroundColor(.red)
            }
        }
        .padding(DesignToken.Spacing.small)
        .appCardSurface(radius: Theme.Radius.control)
    }

    /// Height of the plan in metres. The width is the calibrated scale, so an
    /// imported image contributes its own aspect ratio and a blank plan falls
    /// back to its default footprint. Coverage prediction needs it because the
    /// plan is stretched across the whole pane: one X unit and one Y unit are
    /// not the same number of metres unless the plan is square.
    private var resolvedPlanHeightMeters: Double {
        if let height = survey.project.planHeightMeters { return height }
        let width = survey.project.planWidthMeters ?? 12
        if let image = survey.floorPlanImage, image.size.width > 0 {
            return width * Double(image.size.height / image.size.width)
        }
        return max(4, width * 0.7)
    }

    /// The drawable sheet. An imported floor plan keeps its own aspect ratio so
    /// rooms are not distorted; a hand-drawn plan fills the whole pane, because
    /// it is a metre grid rather than a photograph and used to sit in the middle
    /// of the workspace as a square with empty bands on both sides.
    private func fittedRect(in size: CGSize) -> CGRect {
        if let image = survey.floorPlanImage, image.size.width > 0, image.size.height > 0 {
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let width = image.size.width * scale
            let height = image.size.height * scale
            return CGRect(
                x: (size.width - width) / 2, y: (size.height - height) / 2,
                width: width, height: height)
        }
        return CGRect(origin: .zero, size: size)
    }

    /// One-metre grid for hand-drawn plans, with a label every two metres.
    private func drawPlanGrid(context: GraphicsContext, rect: CGRect) {
        // The sheet is drawn before the grid: on the dark window a bare grid
        // read as empty space, and it was impossible to tell where the plan
        // ended and where a click would land.
        context.fill(Path(rect), with: .color(Color(nsColor: .controlBackgroundColor)))
        let widthMeters = survey.project.planWidthMeters ?? 12
        let heightMeters = resolvedPlanHeightMeters
        var grid = Path()
        let columns = Int(widthMeters.rounded())
        let rows = Int(heightMeters.rounded())
        for column in 0...max(1, columns) {
            let x = rect.minX + CGFloat(Double(column) / widthMeters) * rect.width
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for row in 0...max(1, rows) {
            let y = rect.minY + CGFloat(Double(row) / heightMeters) * rect.height
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.16)), lineWidth: 0.5)

        var border = Path(rect)
        border.closeSubpath()
        context.stroke(border, with: .color(.secondary.opacity(0.35)), lineWidth: 1)

        for column in stride(from: 0, through: columns, by: 2) {
            let x = rect.minX + CGFloat(Double(column) / widthMeters) * rect.width
            context.draw(
                Text("\(column) m").font(.system(size: 8)).foregroundColor(.secondary),
                at: CGPoint(x: x, y: rect.maxY + 7))
        }
        for row in stride(from: 0, through: rows, by: 2) {
            let y = rect.minY + CGFloat(Double(row) / heightMeters) * rect.height
            context.draw(
                Text("\(row) m").font(.system(size: 8)).foregroundColor(.secondary),
                at: CGPoint(x: rect.minX - 12, y: y), anchor: .trailing)
        }
    }

    private func drawSample(context: GraphicsContext, at point: CGPoint, rssi: Int) {
        let color = heatColor(rssi)
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(color)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(.white.opacity(0.8)),
            lineWidth: 1
        )
    }

    private func drawWalls(context: GraphicsContext, rect: CGRect) {
        for wall in survey.walls {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + wall.x1 * rect.width, y: rect.minY + wall.y1 * rect.height))
            path.addLine(
                to: CGPoint(x: rect.minX + wall.x2 * rect.width, y: rect.minY + wall.y2 * rect.height)
            )
            context.stroke(path, with: .color(.orange.opacity(0.9)), lineWidth: 2.5)
        }
        if let start = pendingWallStart {
            context.stroke(
                Path(
                    ellipseIn: CGRect(
                        x: rect.minX + start.x * rect.width - 5,
                        y: rect.minY + start.y * rect.height - 5,
                        width: 10, height: 10
                    )),
                with: .color(.orange),
                lineWidth: 2
            )
        }
    }

    private func heatColor(_ rssi: Int) -> Color {
        let (r, g, b) = HeatPalette.rgb(Double(rssi))
        return Color(red: r, green: g, blue: b)
    }
}

/// Creates a hand-drawn plan: real metre dimensions, no image import.
private struct BlankPlanSheet: View {
    @ObservedObject var survey: SurveyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var width = "12"
    @State private var height = "8"

    private var widthValue: Double? {
        Double(width.replacingOccurrences(of: ",", with: "."))
    }

    private var heightValue: Double? {
        Double(height.replacingOccurrences(of: ",", with: "."))
    }

    private var isValid: Bool {
        guard let widthValue, let heightValue else { return false }
        return (3...200).contains(widthValue) && (3...200).contains(heightValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New blank plan").font(.title3.bold())
            Text(
                "A metre grid you can draw on: add walls and rooms, place predictive APs and click to record signal. No floor-plan image needed."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name").font(.caption).foregroundColor(.secondary)
                    TextField(survey.project.name, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                GridRow {
                    Text("Width (m)").font(.caption).foregroundColor(.secondary)
                    TextField("12", text: $width)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                GridRow {
                    Text("Height (m)").font(.caption).foregroundColor(.secondary)
                    TextField("8", text: $height)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            Text("3–200 m per side. You can recalibrate later from Structure → Calibrate Scale.")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Plan") {
                    guard let widthValue, let heightValue else { return }
                    survey.createBlankPlan(
                        name: name, widthMeters: widthValue, heightMeters: heightValue)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(DesignToken.Layout.sheetPadding)
        .frame(width: DesignToken.Layout.sheetWidthCompact)
    }
}
