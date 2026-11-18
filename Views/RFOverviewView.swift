import SwiftUI

/// All-band RF overview: every nearby access point is drawn as a frequency span
/// on its own band, side by side, so overlap between neighbours is visible
/// without switching tabs.
struct RFOverviewView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var hoveredNetworkId: String?
    @State private var showingChartHelp = false

    private let bands: [WiFiBand] = [.band24, .band5, .band6]

    private func layout(for band: WiFiBand) -> RFOverviewLayout {
        RFOverviewLayout.build(
            band: band,
            networks: viewModel.chartNetworks,
            connectedBSSID: viewModel.currentConnectedBSSID,
            recommendation: viewModel.analysis.bestChannel(for: band)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All bands")
                        .font(.headline)
                    Text("Every nearby access point drawn on its own band.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: DesignToken.Spacing.small)
                Button {
                    showingChartHelp.toggle()
                } label: {
                    Label("What is this?", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Explain this chart")
                .accessibilityLabel("What this chart shows")
                .popover(isPresented: $showingChartHelp, arrowEdge: .bottom) {
                    RFOverviewHelp()
                }
            }

            HStack(alignment: .top, spacing: DesignToken.Spacing.medium) {
                ForEach(bands, id: \.self) { band in
                    RFBandPanel(
                        layout: layout(for: band),
                        selectedNetworkId: viewModel.selectedNetworkId,
                        hoveredNetworkId: $hoveredNetworkId,
                        onSelect: { viewModel.selectedNetworkId = $0 }
                    )
                }
            }
            RFOverviewLegend()
        }
        .padding(DesignToken.Spacing.medium)
    }
}

// MARK: - Chart help

/// "What is this?" popover for the analyzer's main chart: one short paragraph,
/// then the same marks the legend uses, so a new user can read a bar without
/// knowing what a channel width or an overlap region is.
private struct RFOverviewHelp: View {
    private enum Swatch {
        case bar(Color)
        case dashed(Color)
        case region(Color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            Text("Reading the All Bands chart")
                .font(.headline)
            Text(
                "Each band has its own frequency axis. A bar is one access point: it starts at the access point's channel, is as wide as the channel it occupies, and its height is signal strength."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            row(
                .bar(.accentColor), title: "Connected",
                detail: "The network this Mac is joined to.")
            row(
                .bar(AppPalette.band(.band5)), title: "Network width",
                detail: "A wider bar means a wider channel, so it overlaps more neighbours.")
            row(
                .region(AppPalette.warning), title: "Overlapping airtime",
                detail: "Darker regions hold more networks at once — that is where contention builds up.")
            row(
                .dashed(AppPalette.ok), title: "Recommended channel",
                detail:
                    "The quietest usable channel the analyzer found for this band. DFS channels are avoided unless the AP already uses one."
            )

            Divider()
            Text(
                "Click a bar to select that network and show it in the inspector. The legend under the chart repeats these marks."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignToken.Spacing.large)
        .frame(width: 360)
    }

    private func row(_ swatch: Swatch, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.small) {
            Group {
                switch swatch {
                case .bar(let color):
                    RoundedRectangle(cornerRadius: DesignToken.Radius.tiny)
                        .fill(color)
                        .frame(width: 16, height: 8)
                case .dashed(let color):
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundColor(color)
                        .frame(width: 16, height: 8)
                case .region(let color):
                    RoundedRectangle(cornerRadius: DesignToken.Radius.tiny)
                        .fill(color.opacity(0.18))
                        .frame(width: 16, height: 8)
                }
            }
            .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - One band

private struct RFBandPanel: View {
    let layout: RFOverviewLayout
    let selectedNetworkId: String?
    @Binding var hoveredNetworkId: String?
    let onSelect: (String) -> Void

    /// Room under the plot for the channel numbers.
    private let axisHeight: CGFloat = 14
    private let barHeight: CGFloat = 9

    private var bandColor: Color { AppPalette.band(layout.band) }

    var body: some View {
        AppCard(padding: DesignToken.Spacing.medium) {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                header
                plot
                    .frame(minHeight: 130)
                footer
            }
        }
    }

    private var header: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            BandChip(band: layout.band)
            Text("\(layout.spans.count) networks")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: DesignToken.Spacing.tight)
            if let marker = layout.marker {
                StatusPill(
                    text: "\(String(localized: "Best channel")) \(marker.channel)",
                    tone: .good,
                    icon: marker.isDFS ? "wave.3.right" : "checkmark.seal"
                )
            }
        }
    }

    private var plot: some View {
        GeometryReader { geo in
            let size = geo.size
            let domain = layout.domainMHz
            let rect = CGRect(
                x: 0, y: 0,
                width: size.width,
                height: max(0, size.height - axisHeight)
            )
            Canvas { context, _ in
                draw(context: &context, rect: rect, domain: domain)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNetworkId = networkId(at: location, in: rect, domain: domain)
                case .ended:
                    hoveredNetworkId = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if let id = networkId(at: value.location, in: rect, domain: domain) {
                            onSelect(id)
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var footer: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            if let strongest = layout.strongestSignal {
                Text(verbatim: "\(String(localized: "Strongest signal")) \(strongest) dBm")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let busiest = layout.busiestChannel {
                Text(verbatim: "\(String(localized: "Busiest channel")) \(busiest)")
                    .font(.caption2)
                    .foregroundColor(AppPalette.warning)
            }
            Spacer(minLength: 0)
            if layout.maxDepth > 1 {
                Text("\(layout.maxDepth) overlapping")
                    .font(.caption2)
                    .foregroundColor(AppPalette.warning)
            } else {
                Text(String(localized: "No overlap"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var accessibilitySummary: String {
        let count = layout.spans.count
        let overlap = layout.maxDepth > 1 ? "up to \(layout.maxDepth) overlapping" : "no overlap"
        let recommendation = layout.marker.map { ", best channel \($0.channel)" } ?? ""
        return "\(layout.band.label), \(count) networks\(recommendation), \(overlap)"
    }

    // MARK: Drawing

    private func draw(context: inout GraphicsContext, rect: CGRect, domain: ClosedRange<Double>) {
        drawGrid(context: &context, rect: rect, domain: domain)
        drawHotRegions(context: &context, rect: rect, domain: domain)

        if layout.spans.isEmpty {
            context.draw(
                Text(String(localized: "No networks in this band"))
                    .font(.caption)
                    .foregroundColor(.secondary),
                at: CGPoint(x: rect.midX, y: rect.midY),
                anchor: .center
            )
            return
        }

        for span in layout.spans {
            drawSpan(span, context: &context, rect: rect, domain: domain)
        }
        drawMarker(context: &context, rect: rect, domain: domain)
    }

    private func drawGrid(
        context: inout GraphicsContext, rect: CGRect, domain: ClosedRange<Double>
    ) {
        for channel in RFBandGeometry.tickChannels(for: layout.band) {
            guard
                let mhz = RFBandGeometry.centerFrequencyMHz(
                    channel: channel, band: layout.band),
                domain.contains(mhz)
            else { continue }
            let position = x(mhz, in: rect, domain: domain)
            var line = Path()
            line.move(to: CGPoint(x: position, y: rect.minY))
            line.addLine(to: CGPoint(x: position, y: rect.maxY))
            context.stroke(
                line,
                with: .color(Color.secondary.opacity(0.12)),
                lineWidth: DesignToken.Stroke.hairline
            )
            context.draw(
                Text(verbatim: "\(channel)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary),
                at: CGPoint(x: position, y: rect.maxY + DesignToken.Spacing.hairline),
                anchor: .top
            )
        }
    }

    private func drawHotRegions(
        context: inout GraphicsContext, rect: CGRect, domain: ClosedRange<Double>
    ) {
        for region in layout.hotRegions {
            let start = x(region.startMHz, in: rect, domain: domain)
            let end = x(region.endMHz, in: rect, domain: domain)
            let width = max(0.5, end - start)
            let opacity = min(0.26, 0.07 * Double(region.depth))
            context.fill(
                Path(CGRect(x: start, y: rect.minY, width: width, height: rect.height)),
                with: .color(AppPalette.warning.opacity(opacity))
            )
        }
    }

    private func drawSpan(
        _ span: RFOverviewLayout.Span,
        context: inout GraphicsContext,
        rect: CGRect,
        domain: ClosedRange<Double>
    ) {
        let bar = barRect(span, in: rect, domain: domain)
        let base = span.isConnected ? Color.accentColor : bandColor
        let isSelected = span.id == selectedNetworkId
        let isHovered = span.id == hoveredNetworkId
        let fillOpacity: Double = span.isConnected ? 0.85 : (isHovered ? 0.6 : 0.42)
        let path = Path(roundedRect: bar, cornerRadius: DesignToken.Radius.tiny)
        context.fill(path, with: .color(base.opacity(fillOpacity)))
        context.stroke(
            path,
            with: .color(isSelected ? Color.primary : base.opacity(0.9)),
            lineWidth: isSelected ? DesignToken.Stroke.emphasis : DesignToken.Stroke.hairline
        )
    }

    private func drawMarker(
        context: inout GraphicsContext, rect: CGRect, domain: ClosedRange<Double>
    ) {
        guard let marker = layout.marker else { return }
        let center = (marker.startMHz + marker.endMHz) / 2
        let position = x(center, in: rect, domain: domain)
        var line = Path()
        line.move(to: CGPoint(x: position, y: rect.minY))
        line.addLine(to: CGPoint(x: position, y: rect.maxY))
        context.stroke(
            line,
            with: .color(AppPalette.ok.opacity(0.75)),
            style: StrokeStyle(lineWidth: DesignToken.Stroke.hairline, dash: [3, 3])
        )
    }

    // MARK: Geometry and hit testing

    private func x(_ mhz: Double, in rect: CGRect, domain: ClosedRange<Double>) -> CGFloat {
        let span = max(0.001, domain.upperBound - domain.lowerBound)
        let t = (mhz - domain.lowerBound) / span
        return rect.minX + CGFloat(min(max(t, 0), 1)) * rect.width
    }

    private func y(_ signal: Int, in rect: CGRect) -> CGFloat {
        let clamped = Double(min(-35, max(-95, signal)))
        let t = (clamped + 95) / 60
        let usable = max(0, rect.height - barHeight - DesignToken.Spacing.small)
        return rect.maxY - barHeight - CGFloat(t) * usable
    }

    private func barRect(
        _ span: RFOverviewLayout.Span, in rect: CGRect, domain: ClosedRange<Double>
    ) -> CGRect {
        let start = x(span.startMHz, in: rect, domain: domain)
        let end = x(span.endMHz, in: rect, domain: domain)
        return CGRect(
            x: start,
            y: y(span.signal, in: rect),
            width: max(1.5, end - start),
            height: barHeight
        )
    }

    private func networkId(
        at location: CGPoint, in rect: CGRect, domain: ClosedRange<Double>
    ) -> String? {
        guard rect.contains(location) else { return nil }
        return
            layout.spans
            .map { (span: $0, bar: barRect($0, in: rect, domain: domain)) }
            .first { $0.bar.insetBy(dx: -2, dy: -4).contains(location) }?
            .span.id
    }
}

// MARK: - Legend

private struct RFOverviewLegend: View {
    var body: some View {
        HStack(spacing: DesignToken.Spacing.large) {
            item(text: String(localized: "Connected"), color: .accentColor, dashed: false)
            item(text: String(localized: "Network width"), color: .secondary, dashed: false)
            item(text: String(localized: "Overlapping airtime"), color: AppPalette.warning, dashed: false, fading: true)
            item(text: String(localized: "Recommended channel"), color: AppPalette.ok, dashed: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignToken.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private func item(text: String, color: Color, dashed: Bool, fading: Bool = false) -> some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            Group {
                if dashed {
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundColor(color)
                        .frame(width: 14, height: 7)
                } else if fading {
                    RoundedRectangle(cornerRadius: DesignToken.Radius.tiny)
                        .fill(color.opacity(0.18))
                        .frame(width: 14, height: 7)
                } else {
                    RoundedRectangle(cornerRadius: DesignToken.Radius.tiny)
                        .fill(color)
                        .frame(width: 14, height: 7)
                }
            }
            Text(verbatim: text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
