import SwiftUI
import AppKit

struct SurveyView: View {
    @ObservedObject var analyzer: AnalyzerViewModel
    @ObservedObject var survey: SurveyViewModel
    @State private var wallMode = false
    @State private var pendingWallStart: CGPoint?
    @State private var roomMode = false
    @State private var roomPoints: [SurveyPoint] = []
    @State private var walkMode = false
    @State private var lastWalkSample = Date.distantPast
    @State private var showReportSettings = false
    @State private var predictiveMode = false
    @State private var show3DFloors = false
    @State private var calibrating = false
    @State private var calibrationPoints: [SurveyPoint] = []
    @State private var showingClearConfirm = false
    @StateObject private var heatGridCache = HeatGridCache()

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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
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
        .alert("Clear all survey points?", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Points", role: .destructive) { survey.clearSamples() }
        } message: {
            Text("Walls, rooms and predictive access points stay in place.")
        }
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    survey.importFloorPlan()
                } label: {
                    Label("Import Floor Plan", systemImage: "photo")
                }
                .controlSize(.small)

                Button {
                    survey.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)

                Menu {
                    Button("This floor") {
                        survey.exportPDF(
                            networkName: selectedNetwork?.displaySSID ?? "All networks",
                            samples: displayedSamples)
                    }
                    Button("All floors") {
                        survey.exportAllFloorsPDF(networkName: selectedNetwork?.displaySSID ?? "All networks")
                    }
                } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 58)
                .controlSize(.small)

                Button {
                    showReportSettings = true
                } label: {
                    Label("Report", systemImage: "doc.badge.gearshape")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    survey.clearSamples()
                } label: {
                    Label("Clear Points", systemImage: "trash")
                }
                .controlSize(.small)
                .labelStyle(.iconOnly)
                .help("Clear points")
                .disabled(survey.samples.isEmpty)

                Divider().frame(height: 20)

                Button {
                    wallMode.toggle()
                    pendingWallStart = nil
                    survey.statusMessage =
                        wallMode
                        ? String(localized: "Wall mode: click two points to draw a wall.")
                        : String(localized: "Wall mode off.")
                } label: {
                    Label("Draw Wall", systemImage: wallMode ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .help("Draw wall")
                .tint(wallMode ? .orange : nil)

                Button {
                    predictiveMode.toggle()
                    survey.statusMessage =
                        predictiveMode
                        ? String(localized: "Predictive mode: click the plan to place an AP.")
                        : String(localized: "Predictive mode off.")
                } label: {
                    Label(
                        "Predictive",
                        systemImage: predictiveMode
                            ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .help("Predictive mode")
                .tint(predictiveMode ? .purple : nil)

                Button {
                    walkMode.toggle()
                    survey.statusMessage =
                        walkMode
                        ? String(localized: "Walk mode: move the pointer over the plan to sample automatically.")
                        : String(localized: "Walk mode off.")
                } label: {
                    Label("Walk", systemImage: walkMode ? "figure.walk.circle.fill" : "figure.walk")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .help("Walk mode")
                .tint(walkMode ? .green : nil)

                Menu {
                    Button {
                        roomMode.toggle()
                        roomPoints = []
                        survey.statusMessage =
                            roomMode
                            ? String(localized: "Room mode: click vertices, then Finish Room.")
                            : String(localized: "Room mode off.")
                    } label: {
                        Label(roomMode ? "Cancel Room" : "Draw Room", systemImage: "rectangle.dashed")
                    }
                    Button("Finish Room") { finishRoom() }
                        .disabled(roomPoints.count < 3)
                    Button("Clear Rooms", role: .destructive) {
                        survey.clearObstacles()
                        roomPoints = []
                    }
                    .disabled(survey.obstacles.isEmpty)
                    Button("Clear Predictive APs", role: .destructive) {
                        survey.clearAccessPoints()
                    }
                    .disabled(survey.accessPoints.isEmpty)
                    Divider()
                    Button(calibrating ? "Cancel Calibration" : "Calibrate Scale") {
                        calibrating.toggle()
                        calibrationPoints = []
                        survey.statusMessage =
                            calibrating
                            ? String(localized: "Calibration: click two points and enter the real distance.")
                            : String(localized: "Calibration cancelled.")
                    }
                    Divider()
                    Button("Clear Walls", role: .destructive) {
                        survey.clearWalls()
                        pendingWallStart = nil
                    }
                    .disabled(survey.walls.isEmpty)
                } label: {
                    Label("Structure", systemImage: "square.on.square")
                }
                .menuStyle(.borderlessButton)
                .labelStyle(.iconOnly)
                .help("Structure tools")
                .controlSize(.small)

                Spacer()
            }

            HStack(spacing: 10) {
                Divider().frame(height: 20)

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
                .frame(minWidth: 130, maxWidth: 190)
                .controlSize(.small)
                Button {
                    survey.newFloor()
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                .controlSize(.small)
                .help("New floor")
                Button {
                    show3DFloors = true
                } label: {
                    Label("3D", systemImage: "square.3.layers.3d")
                }
                .controlSize(.small)
                .help("Multi-floor 3D view")

                Picker("Network", selection: $survey.selectedNetworkId) {
                    Text("All networks").tag(String?.none)
                    ForEach(analyzer.networks.sorted { $0.signal > $1.signal }) { network in
                        Text("\(network.displaySSID) · \(network.bssid)").tag(Optional(network.id))
                    }
                }
                .frame(minWidth: 240, maxWidth: 360)
                .controlSize(.small)

                if let selectedNetwork {
                    Text("\(selectedNetwork.signal) dBm · \(selectedNetwork.bandLabel) · ch \(selectedNetwork.channel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Material.bar)
    }

    // MARK: - Inspector

    private var surveyInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                metricsCard
                toolCard
                networkCard
                if survey.floorPlanImage != nil {
                    samplesCard
                }
                tipsCard
            }
            .padding(12)
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
            }
        }
    }

    private var toolCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                ToolkitSectionLabel(text: "Current tool")
                HStack(spacing: 7) {
                    Image(systemName: currentToolIcon)
                        .foregroundColor(currentToolTint)
                    Text(currentToolTitle)
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                Text(currentToolHint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private var samplesCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ToolkitSectionLabel(text: "Points")
                    Spacer()
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
                            Spacer()
                            Button {
                                survey.removeSample(id: sample.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                            .buttonStyle(.borderless)
                            .help("Remove point")
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
                tipRow("1", "Import a floor plan.")
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
                .background(Color.accentColor.opacity(0.14), in: Circle())
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentToolTitle: String {
        if calibrating { return String(localized: "Calibrate scale") }
        if predictiveMode { return String(localized: "Predictive AP") }
        if wallMode { return String(localized: "Draw wall") }
        if roomMode { return String(localized: "Draw room") }
        if walkMode { return String(localized: "Walk sampling") }
        return String(localized: "Record sample")
    }

    private var currentToolIcon: String {
        if calibrating { return "ruler" }
        if predictiveMode { return "antenna.radiowaves.left.and.right" }
        if wallMode { return "pencil.tip" }
        if roomMode { return "rectangle.dashed" }
        if walkMode { return "figure.walk" }
        return "hand.tap"
    }

    private var currentToolTint: Color {
        if calibrating { return .cyan }
        if predictiveMode { return .purple }
        if wallMode || roomMode { return .orange }
        if walkMode { return .green }
        return .accentColor
    }

    private var currentToolHint: String {
        if calibrating {
            return String(localized: "Click two points that have a known real-world distance.")
        }
        if predictiveMode {
            return String(
                localized: "Click the plan to place a virtual access point and render predicted coverage."
            )
        }
        if wallMode {
            return String(localized: "Click two points to draw a wall. Walls attenuate the heatmap.")
        }
        if roomMode {
            return String(localized: "Click the room corners, then choose Finish Room from Structure.")
        }
        if walkMode {
            return String(localized: "Move the pointer over the plan to sample automatically as you walk.")
        }
        return String(localized: "Click anywhere on the plan to capture the selected network's signal.")
    }

    @ViewBuilder
    private var content: some View {
        if survey.floorPlanImage == nil {
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
                            detail: "Import a PNG or JPEG. It is copied into the survey project.")
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
                            survey.newFloor()
                        } label: {
                            Label("New Floor", systemImage: "plus.rectangle.on.rectangle")
                        }
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(36)
            }
        } else {
            GeometryReader { geo in
                let rect = fittedRect(in: geo.size)
                let cell: CGFloat = 6
                let columns = max(1, Int(rect.width / cell))
                let rows = max(1, Int(rect.height / cell))
                let heatGrid = heatGridCache.grid(
                    columns: columns, rows: rows,
                    key: heatGridKey(columns: columns, rows: rows)
                ) { column, row in
                    let nx = (Double(column) * Double(cell) + Double(cell) / 2) / Double(rect.width)
                    let ny = (Double(row) * Double(cell) + Double(cell) / 2) / Double(rect.height)
                    return estimateRSSI(nx: nx, ny: ny)
                }
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .underPageBackgroundColor)
                    if let image = survey.floorPlanImage {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                    Canvas { context, _ in
                        drawHeatGrid(context: context, rect: rect, grid: heatGrid, cell: cell)
                        for sample in displayedSamples {
                            let point = CGPoint(
                                x: rect.minX + sample.x * rect.width,
                                y: rect.minY + sample.y * rect.height
                            )
                            drawSample(context: context, at: point, rssi: sample.rssi)
                        }
                        drawWalls(context: context, rect: rect)
                        drawRooms(context: context, rect: rect)
                        drawAccessPoints(context: context, rect: rect)
                        drawCalibration(context: context, rect: rect)
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel(String(localized: "Floor plan heatmap"))
                    .accessibilityValue(
                        String(
                            format: String(
                                localized: "%lld samples, %lld walls, %@"),
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
                    }
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(10)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            legend
                        }
                    }
                    .padding(10)

                    if displayedSamples.isEmpty, !predictiveMode {
                        VStack(spacing: 5) {
                            Image(systemName: "hand.tap")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                            Text("Click anywhere on the plan")
                                .font(.caption.weight(.semibold))
                            Text(
                                captureNetwork?.displaySSID
                                    ?? String(localized: "Start a Wi-Fi scan first")
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard rect.contains(location), rect.width > 0, rect.height > 0 else { return }
                    let x = Double((location.x - rect.minX) / rect.width)
                    let y = Double((location.y - rect.minY) / rect.height)
                    if calibrating {
                        calibrationPoints.append(SurveyPoint(x: x, y: y))
                        if calibrationPoints.count == 2 {
                            finishCalibration()
                        }
                        return
                    }
                    if predictiveMode {
                        let network = captureNetwork
                        survey.addAccessPoint(
                            x: x, y: y,
                            band: network?.band.label ?? "5GHz",
                            channel: network?.channel ?? 36
                        )
                        return
                    }
                    if roomMode {
                        roomPoints.append(SurveyPoint(x: x, y: y))
                        survey.statusMessage = String(
                            format: String(localized: "Room vertices: %lld. Finish Room when ready."),
                            roomPoints.count)
                        return
                    }
                    if wallMode {
                        if let start = pendingWallStart {
                            survey.addWall(x1: Double(start.x), y1: Double(start.y), x2: x, y2: y)
                            pendingWallStart = nil
                        } else {
                            pendingWallStart = CGPoint(x: x, y: y)
                            survey.statusMessage = String(
                                localized: "Wall start set. Click the second point.")
                        }
                        return
                    }
                    guard let network = captureNetwork else { return }
                    survey.addSample(x: x, y: y, network: network)
                }
                .onContinuousHover { phase in
                    guard walkMode, !roomMode, !wallMode, phase != .ended else { return }
                    guard case .active(let location) = phase else { return }
                    guard rect.contains(location), rect.width > 0, rect.height > 0 else { return }
                    let now = Date()
                    guard now.timeIntervalSince(lastWalkSample) >= 0.8 else { return }
                    guard let network = captureNetwork else { return }
                    lastWalkSample = now
                    survey.addSample(
                        x: Double((location.x - rect.minX) / rect.width),
                        y: Double((location.y - rect.minY) / rect.height),
                        network: network
                    )
                }
            }
        }
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
        calibrating = false
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
        roomMode = false
    }

    /// Interpolates one grid cell. Predictive mode (placed access points)
    /// takes precedence over measured samples, matching the previous
    /// drawing behaviour.
    private func estimateRSSI(nx: Double, ny: Double) -> Int? {
        if predictiveMode && !survey.accessPoints.isEmpty {
            let width = survey.project.planWidthMeters ?? 30
            return SurveyPredictor.estimate(
                x: nx, y: ny, accessPoints: survey.accessPoints,
                walls: survey.walls, obstacles: survey.obstacles, planWidthMeters: width
            )
        }
        guard !displayedSamples.isEmpty else { return nil }
        return SurveyInterpolator.estimate(
            x: nx, y: ny, samples: displayedSamples, walls: survey.walls,
            obstacles: survey.obstacles
        )
    }

    /// Fingerprint of everything that invalidates the interpolated grid:
    /// mode, cell geometry and the identity of samples, walls and rooms.
    private func heatGridKey(columns: Int, rows: Int) -> String {
        var parts = [
            "\(columns)x\(rows)",
            "w:\(survey.walls.count):\(survey.walls.map(\.id.uuidString).joined(separator: ","))",
            "o:\(survey.obstacles.count):\(survey.obstacles.map(\.id.uuidString).joined(separator: ","))",
        ]
        if predictiveMode && !survey.accessPoints.isEmpty {
            parts.append("predictive")
            parts.append("ap:\(survey.accessPoints.map(\.id.uuidString).joined(separator: ","))")
            parts.append("plan:\(survey.project.planWidthMeters ?? 30)")
        } else {
            parts.append("measured")
            parts.append("s:\(displayedSamples.map(\.id.uuidString).joined(separator: ","))")
        }
        return parts.joined(separator: "|")
    }

    private func drawHeatGrid(
        context: GraphicsContext, rect: CGRect, grid: HeatGridCache.Grid, cell: CGFloat
    ) {
        let opacity = predictiveMode && !survey.accessPoints.isEmpty ? 0.42 : 0.46
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                guard let rssi = grid.cells[row * grid.columns + column] else { continue }
                context.fill(
                    Path(
                        CGRect(
                            x: rect.minX + CGFloat(column) * cell,
                            y: rect.minY + CGFloat(row) * cell,
                            width: cell + 0.5, height: cell + 0.5
                        )),
                    with: .color(heatColor(rssi).opacity(opacity))
                )
            }
        }
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

    private var legend: some View {
        HStack(spacing: 6) {
            Text("-90").font(.caption2).foregroundColor(.secondary)
            LinearGradient(colors: [.red, .orange, .yellow, .green], startPoint: .leading, endPoint: .trailing)
                .frame(width: 110, height: 7)
                .clipShape(Capsule())
            Text("-40 dBm").font(.caption2).foregroundColor(.secondary)
            Text("· walls/rooms -8 dB").font(.caption2).foregroundColor(.secondary)
            if predictiveMode { Text("· predictive").font(.caption2).foregroundColor(.purple) }
        }
        .padding(7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        guard let image = survey.floorPlanImage, image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
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
