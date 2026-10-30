import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Live hardware-spectrum window: RF Explorer over USB-serial, Wi-Spy
/// device status, and CSV trace import (Chanalyzer exports and generic
/// frequency/dBm tables).
struct HardwareSpectrumView: View {
    @StateObject private var controller = HardwareSpectrumController.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPort: String?
    @State private var statusText = WispyDetector.statusText
    @State private var importError: String?

    private let plotInsets = EdgeInsets(top: 24, leading: 56, bottom: 26, trailing: 16)
    private let amplitudeRange: ClosedRange<Double> = -110...(-20)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let sweep = controller.latestSweep {
                chart(sweep: sweep)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 900, minHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                let ports = controller.availablePorts
                if ports.isEmpty {
                    Text("No serial ports found")
                } else {
                    ForEach(ports, id: \.self) { port in
                        Button("RF Explorer — \(port)") {
                            selectedPort = port
                            controller.connect(portPath: port)
                        }
                    }
                }
                Divider()
                Button("Wi-Spy status: refresh") {
                    statusText = WispyDetector.statusText
                }
                Divider()
                Button("Import CSV Trace…") { importCSV() }
            } label: {
                Label("Source", systemImage: "cable.connector")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if controller.isConnected || controller.state == .connecting {
                Button(controller.isConnected ? "Disconnect" : "Connecting…") {
                    controller.disconnect()
                }
                .disabled(!controller.isConnected)
                .controlSize(.small)
            } else if let port = selectedPort {
                Button("Connect \((port as NSString).lastPathComponent)") {
                    controller.connect(portPath: port)
                }
                .controlSize(.small)
            }

            if !controller.deviceInfo.isEmpty {
                Text(controller.deviceInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("Max Hold", isOn: $controller.useMaxHold)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Button("Reset") { controller.resetMaxHold() }
                .controlSize(.small)
                .disabled(controller.maxHoldSweep == nil)
            Button("Export CSV…") { exportCSV() }
                .controlSize(.small)
                .disabled(controller.latestSweep == nil)
        }
        .padding(10)
        .background(Material.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No hardware spectrum source connected")
                .font(.headline)
            Group {
                if controller.availablePorts.isEmpty {
                    Text(
                        "RF Explorer: no USB-serial port found. Connect the device — it appears as /dev/cu.usbserial-* — then pick it from the Source menu."
                    )
                } else {
                    Text("RF Explorer: choose the serial port from the Source menu to start a live sweep.")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: 460)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: 460)
            Button("Import CSV Trace…") { importCSV() }
                .buttonStyle(.borderedProminent)
            if let importError {
                Text(importError).font(.caption).foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chart

    private func chart(sweep: SpectrumSweep) -> some View {
        GeometryReader { geo in
            let plotRect = CGRect(
                x: plotInsets.leading,
                y: plotInsets.top,
                width: max(0, geo.size.width - plotInsets.leading - plotInsets.trailing),
                height: max(0, geo.size.height - plotInsets.top - plotInsets.bottom)
            )
            Canvas { context, _ in
                drawGrid(context: context, plotRect: plotRect)
                drawChannelGuides(context: context, plotRect: plotRect, sweep: sweep)
                if let hold = controller.maxHoldSweep, hold.isSameGrid(as: sweep) {
                    drawTrace(
                        context: context, plotRect: plotRect, sweep: hold,
                        color: .orange.opacity(0.8), lineWidth: 1.2
                    )
                }
                drawTrace(
                    context: context, plotRect: plotRect, sweep: sweep,
                    color: .accentColor, lineWidth: 1.6
                )
                if let peak = sweep.peak() {
                    let point = pointFor(mhz: peak.mhz, dbm: peak.dbm, plotRect: plotRect, sweep: sweep)
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)),
                        with: .color(.red)
                    )
                    context.draw(
                        Text(String(format: "%.1f dBm @ %.3f MHz", peak.dbm, peak.mhz))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red),
                        at: CGPoint(x: min(point.x + 8, plotRect.maxX - 90), y: max(point.y - 12, plotRect.minY + 8))
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hardware spectrum trace")
            .accessibilityValue(
                String(
                    format: "%.3f to %.3f MHz, %d points, peak %.1f dBm",
                    sweep.startMHz, sweep.endMHz, sweep.pointCount,
                    sweep.peak()?.dbm ?? 0
                )
            )
        }
    }

    private func xFor(mhz: Double, plotRect: CGRect, sweep: SpectrumSweep) -> CGFloat {
        let t = (mhz - sweep.startMHz) / max(sweep.spanMHz, 0.0001)
        return plotRect.minX + CGFloat(min(max(t, 0), 1)) * plotRect.width
    }

    private func yFor(dbm: Double, plotRect: CGRect) -> CGFloat {
        let t = (dbm - amplitudeRange.lowerBound) / (amplitudeRange.upperBound - amplitudeRange.lowerBound)
        return plotRect.maxY - CGFloat(min(max(t, 0), 1)) * plotRect.height
    }

    private func pointFor(mhz: Double, dbm: Double, plotRect: CGRect, sweep: SpectrumSweep) -> CGPoint {
        CGPoint(x: xFor(mhz: mhz, plotRect: plotRect, sweep: sweep), y: yFor(dbm: dbm, plotRect: plotRect))
    }

    private func drawGrid(context: GraphicsContext, plotRect: CGRect) {
        let background = colorScheme == .dark ? Color.black.opacity(0.85) : Color(nsColor: .controlBackgroundColor)
        context.fill(Path(plotRect), with: .color(background))
        for dbm in stride(from: -100.0, through: -30.0, by: 10.0) {
            let y = yFor(dbm: dbm, plotRect: plotRect)
            var line = Path()
            line.move(to: CGPoint(x: plotRect.minX, y: y))
            line.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(line, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            context.draw(
                Text("\(Int(dbm))").font(.system(size: 9)).foregroundColor(.secondary),
                at: CGPoint(x: plotRect.minX - 6, y: y), anchor: .trailing
            )
        }
    }

    private func drawChannelGuides(context: GraphicsContext, plotRect: CGRect, sweep: SpectrumSweep) {
        // 2.4 GHz channels: centre 2412 + 5·(n-1) MHz, 22 MHz wide.
        for channel in 1...13 {
            let center = 2412.0 + 5.0 * Double(channel - 1)
            guard center + 11 > sweep.startMHz, center - 11 < sweep.endMHz else { continue }
            let x1 = xFor(mhz: center - 11, plotRect: plotRect, sweep: sweep)
            let x2 = xFor(mhz: center + 11, plotRect: plotRect, sweep: sweep)
            var band = Path()
            band.move(to: CGPoint(x: x1, y: plotRect.minY))
            band.addLine(to: CGPoint(x: x2, y: plotRect.minY))
            context.stroke(
                band, with: .color(.green.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            context.draw(
                Text("\(channel)").font(.system(size: 8)).foregroundColor(.green.opacity(0.9)),
                at: CGPoint(x: (x1 + x2) / 2, y: plotRect.maxY - 7)
            )
        }
        // 5 GHz channels (U-NII-1/2A/2C/3): standard 20 MHz centres.
        let fiveGHz: [(Int, Double)] = [
            (36, 5180), (40, 5200), (44, 5220), (48, 5240),
            (52, 5260), (56, 5280), (60, 5300), (64, 5320),
            (100, 5500), (104, 5520), (108, 5540), (112, 5560), (116, 5580),
            (120, 5600), (124, 5620), (128, 5640), (132, 5660), (136, 5680), (140, 5700),
            (149, 5745), (153, 5765), (157, 5785), (161, 5805), (165, 5805 + 20),
        ]
        for (channel, center) in fiveGHz {
            guard center + 10 > sweep.startMHz, center - 10 < sweep.endMHz else { continue }
            let x1 = xFor(mhz: center - 10, plotRect: plotRect, sweep: sweep)
            let x2 = xFor(mhz: center + 10, plotRect: plotRect, sweep: sweep)
            var band = Path()
            band.move(to: CGPoint(x: x1, y: plotRect.minY))
            band.addLine(to: CGPoint(x: x2, y: plotRect.minY))
            context.stroke(
                band, with: .color(.blue.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            context.draw(
                Text("\(channel)").font(.system(size: 8)).foregroundColor(.blue.opacity(0.9)),
                at: CGPoint(x: (x1 + x2) / 2, y: plotRect.minY + 7)
            )
        }
    }

    private func drawTrace(
        context: GraphicsContext, plotRect: CGRect, sweep: SpectrumSweep, color: Color, lineWidth: CGFloat
    ) {
        guard sweep.pointCount > 1 else { return }
        var path = Path()
        for index in sweep.amplitudes.indices {
            let point = pointFor(
                mhz: sweep.frequencyMHz(at: index), dbm: sweep.amplitudes[index],
                plotRect: plotRect, sweep: sweep
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: - Import / Export

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .commaSeparatedText, .plainText, UTType(filenameExtension: "csv"),
        ].compactMap { $0 }
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                let text = try? String(contentsOf: url, encoding: .utf8),
                let sweep = SpectrumCSVImporter.parse(text, source: url.lastPathComponent)
            else {
                importError = "Could not read a frequency/dBm table from the selected file."
                return
            }
            importError = nil
            controller.loadImport(sweep)
        }
    }

    private func exportCSV() {
        guard let sweep = controller.latestSweep else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LanFi spectrum \(Int(sweep.startMHz))-\(Int(sweep.endMHz)) MHz.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? SpectrumCSVExporter.csv(sweep).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
