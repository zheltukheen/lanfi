import AppKit
import Foundation

enum SurveyReportExporter {
    static func makePDF(project: SurveyProject, image: NSImage?, networkName: String) -> Data {
        let page = NSSize(width: 842, height: 595)  // A4 landscape at 72 dpi
        let view = SurveyReportView(
            frame: NSRect(origin: .zero, size: page),
            project: project,
            image: image,
            networkName: networkName
        )
        return view.dataWithPDF(inside: view.bounds)
    }
}

private final class SurveyReportView: NSView {
    let project: SurveyProject
    let image: NSImage?
    let networkName: String

    init(frame: NSRect, project: SurveyProject, image: NSImage?, networkName: String) {
        self.project = project
        self.image = image
        self.networkName = networkName
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let title = "LanFi Site Survey — \(project.name)"
        title.draw(
            at: NSPoint(x: 28, y: bounds.height - 42),
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 20),
                .foregroundColor: NSColor.black,
            ]
        )
        let subtitle =
            "\(networkName) · \(project.samples.count) samples · \(project.walls.count) walls · \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))"
        subtitle.draw(
            at: NSPoint(x: 28, y: bounds.height - 62),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.darkGray]
        )

        let planRect = NSRect(x: 28, y: 72, width: bounds.width - 56, height: bounds.height - 150)
        if let image {
            let fitted = aspectFit(image.size, in: planRect)
            image.draw(in: fitted, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            drawHeatmap(in: fitted)
            drawWalls(in: fitted)
        } else {
            NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
            planRect.fill()
            "No floor plan".draw(
                at: NSPoint(x: planRect.midX - 40, y: planRect.midY),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.gray]
            )
        }

        let legend = "RSSI:  -90 dBm (red)  →  -40 dBm (green)     walls: -8 dB each"
        legend.draw(
            at: NSPoint(x: 28, y: 42),
            withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray]
        )
    }

    private func drawHeatmap(in rect: NSRect) {
        guard !project.samples.isEmpty else { return }
        let cell: CGFloat = 7
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let nx = Double((x - rect.minX) / rect.width)
                let ny = Double((y - rect.minY) / rect.height)
                if let rssi = SurveyInterpolator.estimate(
                    x: nx, y: ny, samples: project.samples, walls: project.walls
                ) {
                    color(for: rssi).withAlphaComponent(0.48).setFill()
                    NSRect(x: x, y: y, width: cell + 0.5, height: cell + 0.5).fill()
                }
                x += cell
            }
            y += cell
        }
        for sample in project.samples {
            let point = NSPoint(
                x: rect.minX + sample.x * rect.width,
                y: rect.minY + (1 - sample.y) * rect.height
            )
            color(for: sample.rssi).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
        }
    }

    private func drawWalls(in rect: NSRect) {
        NSColor.orange.setStroke()
        for wall in project.walls {
            let path = NSBezierPath()
            path.move(
                to: NSPoint(
                    x: rect.minX + wall.x1 * rect.width,
                    y: rect.minY + (1 - wall.y1) * rect.height
                ))
            path.line(
                to: NSPoint(
                    x: rect.minX + wall.x2 * rect.width,
                    y: rect.minY + (1 - wall.y2) * rect.height
                ))
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func aspectFit(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return NSRect(
            x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height
        )
    }

    private func color(for rssi: Int) -> NSColor {
        switch rssi {
        case (-50)...: return .systemGreen
        case (-65)...: return .systemYellow
        case (-78)...: return .systemOrange
        default: return .systemRed
        }
    }
}
