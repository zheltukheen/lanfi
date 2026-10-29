import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryExportMenu: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    private var networks: [NetworkModel] { viewModel.chartNetworks }

    var body: some View {
        Menu {
            Button("PNG…") { exportPNG() }
            Button("SVG…") { exportSVG() }
            Button("CSV…") { exportCSV() }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Export history")
    }

    private func exportPNG() {
        let renderer = ImageRenderer(
            content: SignalHistoryView(viewModel: viewModel).frame(width: 1400, height: 700)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { return }
        save(data, name: "LanFi-History.png", type: .png)
    }

    private func exportSVG() {
        let histories = networks.compactMap { network -> (NetworkModel, [Int])? in
            guard let history = viewModel.signalHistory[network.id], !history.isEmpty else { return nil }
            return (network, history)
        }
        let width = 1200.0, height = 600.0
        let all = histories.flatMap(\.1)
        let minValue = Double(all.min() ?? -100) - 4
        let maxValue = Double(all.max() ?? 0) + 4
        let count = max(1, histories.map(\.1.count).max() ?? 1)
        var svg =
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\"><rect width=\"100%\" height=\"100%\" fill=\"white\"/>"
        svg += "<text x=\"24\" y=\"30\" font-family=\"sans-serif\" font-size=\"18\" fill=\"black\">LanFi history</text>"
        for (network, history) in histories {
            let color = String(format: "#%06X", abs(network.id.hashValue) & 0xFFFFFF)
            let points = history.enumerated().map { index, value -> String in
                let x = 60 + Double(index) / Double(max(count - 1, 1)) * (width - 100)
                let y = 60 + (maxValue - Double(value)) / max(maxValue - minValue, 1) * (height - 120)
                return "\(String(format: "%.1f", x)),\(String(format: "%.1f", y))"
            }.joined(separator: " ")
            svg += "<polyline points=\"\(points)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"2\"/>"
            svg +=
                "<text x=\"70\" y=\"\(70 + Double(histories.firstIndex(where: { $0.0.id == network.id }) ?? 0) * 16)\" font-family=\"sans-serif\" font-size=\"10\" fill=\"\(color)\">\(escape(network.displaySSID))</text>"
        }
        svg += "</svg>"
        save(Data(svg.utf8), name: "LanFi-History.svg", type: .svg)
    }

    private func exportCSV() {
        let maxCount = networks.map { viewModel.signalHistory[$0.id]?.count ?? 0 }.max() ?? 0
        var rows = [["Sample"] + networks.map(\.displaySSID)]
        for index in 0..<maxCount {
            rows.append(
                [String(index)]
                    + networks.map { network in
                        viewModel.signalHistory[network.id].flatMap { index < $0.count ? String($0[index]) : "" } ?? ""
                    })
        }
        let csv = rows.map {
            $0.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
        }
        .joined(separator: "\r\n")
        save(Data(("\u{FEFF}" + csv + "\r\n").utf8), name: "LanFi-History.csv", type: .commaSeparatedText)
    }

    private func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}
