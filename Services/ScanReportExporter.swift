import AppKit
import Foundation

enum ScanReportExporter {
    static func makePDF(
        title: String, networks: [NetworkModel], columns: [ColumnDefinition],
        text: @escaping (String, NetworkModel) -> String
    ) -> Data {
        let visible = columns.sorted { $0.order < $1.order }.filter { $0.isVisible }
        let rowHeight: CGFloat = 16
        let pageWidth: CGFloat = 842
        let height = max(595, 90 + CGFloat(networks.count + 1) * rowHeight + 30)
        let view = ScanPDFView(
            frame: NSRect(x: 0, y: 0, width: pageWidth, height: height),
            title: title, networks: networks, columns: visible, text: text
        )
        return view.dataWithPDF(inside: view.bounds)
    }
}

private final class ScanPDFView: NSView {
    let title: String
    let networks: [NetworkModel]
    let columns: [ColumnDefinition]
    let text: (String, NetworkModel) -> String

    init(
        frame: NSRect, title: String, networks: [NetworkModel], columns: [ColumnDefinition],
        text: @escaping (String, NetworkModel) -> String
    ) {
        self.title = title
        self.networks = networks
        self.columns = columns
        self.text = text
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let margin: CGFloat = 24
        let contentWidth = bounds.width - margin * 2
        let weights = columns.map { max($0.width, 40) }
        let total = weights.reduce(0, +)
        var xs: [CGFloat] = []
        var x = margin
        for weight in weights {
            xs.append(x)
            x += contentWidth * weight / max(total, 1)
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.black,
        ]
        title.draw(at: NSPoint(x: margin, y: bounds.height - 34), withAttributes: titleAttributes)
        let dateText = ISO8601DateFormatter().string(from: Date())
        dateText.draw(
            at: NSPoint(x: margin, y: bounds.height - 52),
            withAttributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.darkGray]
        )

        let headerFont = NSFont.boldSystemFont(ofSize: 8)
        let bodyFont = NSFont.systemFont(ofSize: 7)
        var y = bounds.height - 76
        for (index, column) in columns.enumerated() {
            (column.displayTitle as NSString).draw(
                at: NSPoint(x: xs[index], y: y),
                withAttributes: [.font: headerFont, .foregroundColor: NSColor.black]
            )
        }
        y -= 4
        NSColor.gray.setFill()
        NSRect(x: margin, y: y, width: contentWidth, height: 0.5).fill()
        y -= 14

        for network in networks {
            if y < 24 { break }
            for (index, column) in columns.enumerated() {
                let value = text(column.id, network)
                (String(value.prefix(70)) as NSString).draw(
                    at: NSPoint(x: xs[index], y: y),
                    withAttributes: [.font: bodyFont, .foregroundColor: NSColor.black]
                )
            }
            y -= 14
            NSColor.gray.withAlphaComponent(0.2).setFill()
            NSRect(x: margin, y: y + 8, width: contentWidth, height: 0.3).fill()
        }
    }
}
