import SwiftUI

struct SpectrumView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var zoom = 1.0
    @Environment(\.openWindow) private var openWindow
    var isFullScreen = false

    private let plotInsets = EdgeInsets(top: 58, leading: 62, bottom: 40, trailing: 16)
    private var baseDomain: ClosedRange<Double> {
        0...(max(lanes.last?.end ?? 1, 1) + 0.19)
    }

    private var displayDomain: ClosedRange<Double> {
        let center = (baseDomain.lowerBound + baseDomain.upperBound) / 2
        let half = (baseDomain.upperBound - baseDomain.lowerBound) / (2 * max(zoom, 1))
        return (center - half)...(center + half)
    }

    private var spectrumBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.9) : Color(nsColor: .controlBackgroundColor)
    }

    private var networks: [NetworkModel] { viewModel.chartNetworks }

    private struct BandLane {
        let band: WiFiBand
        let start: Double
        let end: Double
        let minChannel: Double
        let maxChannel: Double
        let label: String
        let ticks: [Int]
    }

    private var lanes: [BandLane] {
        let supported = viewModel.supportedChannels
        let orderedBands: [WiFiBand] = [.band24, .band5, .band6, .unknown]
        var result: [BandLane] = []
        var position = 0.0
        for band in orderedBands {
            let supportedChannels = supported.filter { $0.band == band }.map(\.channel).sorted()
            let visibleChannels = networks.filter { $0.band == band }.map(\.channel).sorted()
            let channels = Array(Set(supportedChannels + visibleChannels)).sorted()
            guard !channels.isEmpty else { continue }
            let start = position
            let end = position + 1.0
            let ticks = tickChannels(channels)
            result.append(
                BandLane(
                    band: band,
                    start: start,
                    end: end,
                    minChannel: Double(channels.first ?? 0),
                    maxChannel: Double(channels.last ?? 0),
                    label: bandLabel(band),
                    ticks: ticks
                )
            )
            position = end + 0.08
        }
        return result
    }

    private func tickChannels(_ channels: [Int]) -> [Int] {
        guard channels.count > 9 else { return channels }
        let step = max(1, channels.count / 8)
        var ticks = stride(from: 0, to: channels.count, by: step).map { channels[$0] }
        if !ticks.contains(channels.last!) { ticks.append(channels.last!) }
        return ticks
    }

    private func bandLabel(_ band: WiFiBand) -> String {
        switch band {
        case .band24: return "2.4 GHz"
        case .band5: return "5 GHz"
        case .band6: return "6 GHz"
        case .unknown: return "Other"
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                spectrumBackground.edgesIgnoringSafeArea(.all)
                let plotRect = CGRect(
                    x: plotInsets.leading,
                    y: plotInsets.top,
                    width: max(0, geo.size.width - plotInsets.leading - plotInsets.trailing),
                    height: max(0, geo.size.height - plotInsets.top - plotInsets.bottom)
                )

                Canvas { context, _ in
                    drawGridAndAxis(context: context, plotRect: plotRect)
                    let sorted = networks.sorted { lhs, rhs in
                        if lhs.id == viewModel.selectedNetworkId { return false }
                        if rhs.id == viewModel.selectedNetworkId { return true }
                        return lhs.signal < rhs.signal
                    }
                    let hasSelection = sorted.contains { $0.id == viewModel.selectedNetworkId }
                    for network in sorted {
                        drawNetwork(context: context, plotRect: plotRect, network: network, dimOthers: hasSelection)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: networks)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Spectrum, all bands, \(networks.count) networks")
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            selectNetworkAt(location: value.location, plotRect: plotRect)
                        }
                )
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 10) {
                        Text("All bands · \(networks.count) networks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        SpectrumExportMenu(viewModel: viewModel, networks: networks)
                        Button {
                            zoom = min(4, zoom * 1.25)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .buttonStyle(.borderless).disabled(zoom >= 4)
                        Button {
                            zoom = max(0.5, zoom / 1.25)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .buttonStyle(.borderless).disabled(zoom <= 0.5)
                        if isFullScreen {
                            Button {
                                NSApp.keyWindow?.toggleFullScreen(nil)
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Button {
                                openWindow(id: "spectrum")
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
            }
        }
        .onChange(of: viewModel.networks.count) { _ in }
        .onAppear {
            guard isFullScreen else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
    }

    private func lane(for network: NetworkModel) -> BandLane? {
        lanes.first { $0.band == network.band }
    }

    private func xPosition(for network: NetworkModel, plotRect: CGRect) -> CGFloat {
        guard let lane = lane(for: network) else { return plotRect.midX }
        let t = (Double(network.channel) - lane.minChannel) / max(1, lane.maxChannel - lane.minChannel)
        let normalized = lane.start + min(max(t, 0), 1) * (lane.end - lane.start)
        return plotRect.minX + CGFloat(
            (normalized - displayDomain.lowerBound) / (displayDomain.upperBound - displayDomain.lowerBound))
            * plotRect.width
    }

    private func width(for network: NetworkModel, plotRect: CGRect) -> CGFloat {
        guard let lane = lane(for: network) else { return 4 }
        let spanMHz = (lane.maxChannel - lane.minChannel + 1) * 5
        let fraction = min(1, Double(max(network.channelWidthMHz, 20)) / spanMHz)
        return CGFloat(fraction * (lane.end - lane.start) / (displayDomain.upperBound - displayDomain.lowerBound))
            * plotRect.width
    }

    private func xForValue(_ value: Double, plotRect: CGRect) -> CGFloat {
        plotRect.minX + CGFloat(
            (value - displayDomain.lowerBound) / (displayDomain.upperBound - displayDomain.lowerBound)) * plotRect.width
    }

    private func yPosition(dbm: Double, plotRect: CGRect) -> CGFloat {
        let clamped = max(-100, min(-10, dbm))
        let normalized = (-10 - clamped) / 90
        return plotRect.minY + CGFloat(normalized) * plotRect.height
    }

    private func yPosition(percent: Double, plotRect: CGRect) -> CGFloat {
        let clamped = max(0, min(100, percent))
        let usable = plotRect.height * 0.92
        return plotRect.minY + plotRect.height * 0.04 + CGFloat((100 - clamped) / 100) * usable
    }

    private func drawGridAndAxis(context: GraphicsContext, plotRect: CGRect) {
        let isPercent = viewModel.signalDisplayMode == .percent
        let levels: [Double] =
            isPercent
            ? [0, 25, 50, 75, 100]
            : [-100, -90, -80, -70, -60, -50, -40, -30, -20, -10]

        var axis = Path()
        axis.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
        axis.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        context.stroke(axis, with: .color(.secondary.opacity(0.45)), lineWidth: 1)

        for level in levels {
            let y =
                isPercent ? yPosition(percent: level, plotRect: plotRect) : yPosition(dbm: level, plotRect: plotRect)
            var path = Path()
            path.move(to: CGPoint(x: plotRect.minX, y: y))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(
                path, with: .color(.primary.opacity(level == -100 || level == 0 ? 0.20 : 0.10)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            let label = isPercent ? "\(Int(level))%" : "\(Int(level))"
            context.draw(
                Text(label).font(.caption2.monospacedDigit()).foregroundColor(.secondary),
                at: CGPoint(x: plotRect.minX - 8, y: y), anchor: .trailing
            )
        }
        context.draw(
            Text(isPercent ? "Signal %" : "dBm").font(.caption2.bold()).foregroundColor(.secondary),
            at: CGPoint(x: plotRect.minX - 8, y: plotRect.minY - 16), anchor: .trailing
        )

        let active = Set(networks.map(\.channel))
        for lane in lanes {
            let startX = xForValue(lane.start, plotRect: plotRect)
            let endX = xForValue(lane.end, plotRect: plotRect)
            var divider = Path()
            divider.move(to: CGPoint(x: startX, y: plotRect.minY))
            divider.addLine(to: CGPoint(x: startX, y: plotRect.maxY + 14))
            context.stroke(divider, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            context.draw(
                Text(lane.label).font(.caption2.bold()).foregroundColor(.secondary),
                at: CGPoint(x: (startX + endX) / 2, y: plotRect.maxY + 26)
            )
            for channel in lane.ticks {
                let t = (Double(channel) - lane.minChannel) / max(1, lane.maxChannel - lane.minChannel)
                let value = lane.start + min(max(t, 0), 1) * (lane.end - lane.start)
                let x = xForValue(value, plotRect: plotRect)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: plotRect.maxY))
                tick.addLine(to: CGPoint(x: x, y: plotRect.maxY + 4))
                context.stroke(tick, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
                context.draw(
                    Text("\(channel)").font(.caption2).foregroundColor(
                        active.contains(channel) ? .primary : .secondary),
                    at: CGPoint(x: x, y: plotRect.maxY + 15)
                )
            }
        }
    }

    private func drawNetwork(
        context: GraphicsContext, plotRect: CGRect, network: NetworkModel, dimOthers: Bool
    ) {
        let isSelected = network.id == viewModel.selectedNetworkId
        let isDimmed = dimOthers && !isSelected
        let centerX = xPosition(for: network, plotRect: plotRect)
        let w = max(4, width(for: network, plotRect: plotRect))
        let signal = max(-100, min(-20, Double(network.signal)))
        let isPercent = viewModel.signalDisplayMode == .percent
        let peakY =
            isPercent
            ? yPosition(percent: viewModel.convertToPercent(Int(signal)), plotRect: plotRect)
            : yPosition(dbm: signal, plotRect: plotRect)
        let floorY = isPercent ? yPosition(percent: 0, plotRect: plotRect) : plotRect.maxY
        let halfBase = w / 2
        let halfTop = halfBase * 0.85
        var path = Path()
        path.move(to: CGPoint(x: centerX - halfBase, y: floorY))
        path.addLine(to: CGPoint(x: centerX - halfTop, y: peakY))
        path.addLine(to: CGPoint(x: centerX + halfTop, y: peakY))
        path.addLine(to: CGPoint(x: centerX + halfBase, y: floorY))

        let baseColor = viewModel.colorFor(networkId: network.id)
        let strokeColor = isDimmed ? baseColor.opacity(0.2) : baseColor
        let fillColor = isSelected ? baseColor.opacity(0.3) : (isDimmed ? Color.clear : baseColor.opacity(0.05))
        if isSelected {
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [fillColor, fillColor.opacity(0.1)]),
                    startPoint: CGPoint(x: centerX, y: peakY),
                    endPoint: CGPoint(x: centerX, y: floorY)
                )
            )
        } else {
            context.fill(path, with: .color(fillColor))
        }
        context.stroke(path, with: .color(strokeColor), lineWidth: isSelected ? 2.5 : (isDimmed ? 1 : 1.5))
        if isSelected || (!isDimmed && w > 18) {
            context.draw(
                Text(network.displayName)
                    .font(isSelected ? .system(size: 11, weight: .bold) : .system(size: 9))
                    .foregroundColor(isSelected ? strokeColor : strokeColor.opacity(0.8)),
                at: CGPoint(x: centerX, y: peakY - (isSelected ? 12 : 8)), anchor: .bottom
            )
        }
    }

    private func selectNetworkAt(location: CGPoint, plotRect: CGRect) {
        let visible = networks.filter {
            let center = xPosition(for: $0, plotRect: plotRect)
            let half = width(for: $0, plotRect: plotRect) / 2
            return abs(location.x - center) <= max(half, 8)
        }
        let best = visible.min {
            abs(location.x - xPosition(for: $0, plotRect: plotRect))
                < abs(location.x - xPosition(for: $1, plotRect: plotRect))
        }
        viewModel.selectedNetworkId = best?.id
    }
}
