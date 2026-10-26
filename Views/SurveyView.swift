import SwiftUI
import AppKit

struct SurveyView: View {
    @ObservedObject var analyzer: AnalyzerViewModel
    @ObservedObject var survey: SurveyViewModel

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

            Text(survey.statusMessage)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
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
                        for sample in displayedSamples {
                            let point = CGPoint(
                                x: rect.minX + sample.x * rect.width,
                                y: rect.minY + sample.y * rect.height
                            )
                            drawHeat(context: context, at: point, rssi: sample.rssi)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel("Floor plan heatmap")
                    .accessibilityValue(
                        "\(displayedSamples.count) samples, \(selectedNetwork?.displaySSID ?? "all networks")")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedNetwork?.displaySSID ?? "All networks")
                            .font(.caption.bold())
                        Text("\(displayedSamples.count) points")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
                    guard let network = captureNetwork, rect.contains(location), rect.width > 0, rect.height > 0 else {
                        return
                    }
                    let x = (location.x - rect.minX) / rect.width
                    let y = (location.y - rect.minY) / rect.height
                    survey.addSample(x: Double(x), y: Double(y), network: network)
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

    private func drawHeat(context: GraphicsContext, at point: CGPoint, rssi: Int) {
        let color = heatColor(rssi)
        let radius: CGFloat = 38
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let gradient = Gradient(colors: [color.opacity(0.55), color.opacity(0.0)])
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(gradient, center: point, startRadius: 0, endRadius: radius)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(color)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(.white.opacity(0.7)),
            lineWidth: 1
        )
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
