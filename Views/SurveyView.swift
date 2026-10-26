import SwiftUI
import AppKit

struct SurveyView: View {
    @ObservedObject var analyzer: AnalyzerViewModel
    @ObservedObject var survey: SurveyViewModel
    @State private var wallMode = false
    @State private var pendingWallStart: CGPoint?

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
            content
        }
        .frame(minWidth: 900, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
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

            Button(role: .destructive) {
                survey.clearSamples()
            } label: {
                Label("Clear Points", systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(survey.samples.isEmpty)

            Divider().frame(height: 20)

            Button {
                wallMode.toggle()
                pendingWallStart = nil
                survey.statusMessage =
                    wallMode
                    ? "Wall mode: click two points to draw a wall."
                    : "Wall mode off."
            } label: {
                Label("Draw Wall", systemImage: wallMode ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(wallMode ? .orange : nil)

            Button(role: .destructive) {
                survey.clearWalls()
                pendingWallStart = nil
            } label: {
                Label("Clear Walls", systemImage: "rectangle.portrait.slash")
            }
            .controlSize(.small)
            .disabled(survey.walls.isEmpty)

            Divider().frame(height: 20)

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
        .padding(10)
        .background(Material.bar)
    }

    @ViewBuilder
    private var content: some View {
        if survey.floorPlanImage == nil {
            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.35))
                Text("No floor plan loaded")
                    .font(.headline)
                Text(
                    "Import a PNG or JPEG floor plan, then click anywhere on it to record the selected network's RSSI."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                Button("Import Floor Plan") { survey.importFloorPlan() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let rect = fittedRect(in: geo.size)
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
                        drawInterpolatedHeat(context: context, rect: rect)
                        for sample in displayedSamples {
                            let point = CGPoint(
                                x: rect.minX + sample.x * rect.width,
                                y: rect.minY + sample.y * rect.height
                            )
                            drawSample(context: context, at: point, rssi: sample.rssi)
                        }
                        drawWalls(context: context, rect: rect)
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel("Floor plan heatmap")
                    .accessibilityValue(
                        "\(displayedSamples.count) samples, \(survey.walls.count) walls, "
                            + "\(selectedNetwork?.displaySSID ?? "all networks")")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedNetwork?.displaySSID ?? "All networks")
                            .font(.caption.bold())
                        Text("\(displayedSamples.count) points · \(survey.walls.count) walls")
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
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard rect.contains(location), rect.width > 0, rect.height > 0 else { return }
                    let x = Double((location.x - rect.minX) / rect.width)
                    let y = Double((location.y - rect.minY) / rect.height)
                    if wallMode {
                        if let start = pendingWallStart {
                            survey.addWall(x1: Double(start.x), y1: Double(start.y), x2: x, y2: y)
                            pendingWallStart = nil
                        } else {
                            pendingWallStart = CGPoint(x: x, y: y)
                            survey.statusMessage = "Wall start set. Click the second point."
                        }
                        return
                    }
                    guard let network = captureNetwork else { return }
                    survey.addSample(x: x, y: y, network: network)
                }
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
            Text("· walls -8 dB").font(.caption2).foregroundColor(.secondary)
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

    private func drawInterpolatedHeat(context: GraphicsContext, rect: CGRect) {
        guard !displayedSamples.isEmpty else { return }
        let cell: CGFloat = 6
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let nx = Double((x - rect.minX) / rect.width)
                let ny = Double((y - rect.minY) / rect.height)
                if let rssi = SurveyInterpolator.estimate(
                    x: nx, y: ny, samples: displayedSamples, walls: survey.walls
                ) {
                    let color = heatColor(rssi)
                    context.fill(
                        Path(CGRect(x: x, y: y, width: cell + 0.5, height: cell + 0.5)),
                        with: .color(color.opacity(0.46))
                    )
                }
                x += cell
            }
            y += cell
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
        switch rssi {
        case (-50)...: return .green
        case (-65)...: return .yellow
        case (-78)...: return .orange
        default: return .red
        }
    }
}
