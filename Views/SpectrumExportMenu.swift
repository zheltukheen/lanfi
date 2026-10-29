import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SpectrumExportMenu: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    let networks: [NetworkModel]

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
        .help("Export spectrum")
    }

    private func exportPNG() {
        let view = SpectrumView(viewModel: viewModel).frame(width: 1400, height: 700)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { return }
        save(data, name: "LanFi-Spectrum.png", type: .png)
    }

    private func exportSVG() {
        let svg = SpectrumSVG.make(networks: networks)
        save(Data(svg.utf8), name: "LanFi-Spectrum.svg", type: UTType(filenameExtension: "svg") ?? .svg)
    }

    private func exportCSV() {
        let rows =
            [["SSID", "BSSID", "Band", "Channel", "WidthMHz", "Signal", "Noise", "SNR"]]
            + networks.map {
                [
                    $0.displaySSID, $0.bssid, $0.band.label, String($0.channel), String($0.channelWidthMHz),
                    String($0.signal), $0.noise.map(String.init) ?? "", $0.snr.map(String.init) ?? "",
                ]
            }
        let csv = rows.map {
            $0.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
        }
        .joined(separator: "\r\n")
        save(Data(("\u{FEFF}" + csv + "\r\n").utf8), name: "LanFi-Spectrum.csv", type: .commaSeparatedText)
    }

    private func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum SpectrumSVG {
    static func make(networks: [NetworkModel]) -> String {
        let width = 1200.0, height = 600.0
        var svg =
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\"><rect width=\"100%\" height=\"100%\" fill=\"white\"/>"
        svg +=
            "<text x=\"20\" y=\"28\" font-family=\"sans-serif\" font-size=\"18\" fill=\"black\">LanFi spectrum</text>"
        for (index, network) in networks.enumerated() {
            let x = 60 + Double(index % 20) * 54
            let y = 80 + Double(index / 20) * 60
            let color = String(format: "#%06X", (viewModelColor(network.id) & 0xFFFFFF))
            svg +=
                "<rect x=\"\(x)\" y=\"\(y)\" width=\"48\" height=\"36\" rx=\"5\" fill=\"\(color)\" opacity=\"0.25\" stroke=\"\(color)\"/>"
            svg +=
                "<text x=\"\(x + 3)\" y=\"\(y + 16)\" font-family=\"sans-serif\" font-size=\"9\" fill=\"black\">\(escape(network.displaySSID.prefix(10)))</text>"
            svg +=
                "<text x=\"\(x + 3)\" y=\"\(y + 28)\" font-family=\"sans-serif\" font-size=\"8\" fill=\"#555\">\(network.channel) · \(network.signal) dBm</text>"
        }
        svg += "</svg>"
        return svg
    }

    private static func viewModelColor(_ id: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return hash
    }

    private static func escape(_ value: some StringProtocol) -> String {
        String(value).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}
