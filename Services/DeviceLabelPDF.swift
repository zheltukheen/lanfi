import AppKit
import Foundation

/// Renders a printable sheet of device labels: one QR per device, each encoding
/// a `lanfi://device/<assetTag>` link instead of a MAC address.
enum DeviceLabelPDF {
    static let pageSize = CGSize(width: 612, height: 792)  // US Letter, points
    private static let margin: CGFloat = 36
    private static let columns = 2
    private static let rows = 4
    private static let gap: CGFloat = 12

    static func data(for devices: [ShelfDevice], generatedAt: Date = Date()) -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return Data() }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            return Data()
        }

        let perPage = columns * rows
        let pages = max(1, Int(ceil(Double(devices.count) / Double(perPage))))
        for page in 0..<pages {
            context.beginPDFPage(nil)
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics

            drawPageHeader(generatedAt: generatedAt, page: page + 1, of: pages)
            let start = page * perPage
            let slice = devices.dropFirst(start).prefix(perPage)
            for (index, device) in slice.enumerated() {
                let column = index % columns
                let row = index / columns
                let rect = labelRect(column: column, row: row)
                drawLabel(device, in: rect)
            }

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// Saves a single QR as PNG for a sticker printer or a chat message.
    static func png(for tag: String, size: CGFloat = 512) -> Data? {
        guard let image = QRCode.image(for: DeviceShelfAsset.deepLink(for: tag), scale: 12) else {
            return nil
        }
        let target = NSImage(size: NSSize(width: size, height: size))
        target.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - Drawing

    private static func labelRect(column: Int, row: Int) -> CGRect {
        let width = (pageSize.width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (pageSize.height - margin * 2 - 48 - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return CGRect(
            x: margin + CGFloat(column) * (width + gap),
            y: pageSize.height - margin - 40 - CGFloat(row + 1) * height - CGFloat(row) * gap,
            width: width,
            height: height
        )
    }

    private static func drawPageHeader(generatedAt: Date, page: Int, of pages: Int) {
        let title = NSAttributedString(
            string: "LanFi · device labels",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        title.draw(at: CGPoint(x: margin, y: pageSize.height - margin + 6))
        let stamp = NSAttributedString(
            string: "\(generatedAt.formatted(date: .abbreviated, time: .shortened)) · page \(page)/\(pages)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
        let size = stamp.size()
        stamp.draw(at: CGPoint(x: pageSize.width - margin - size.width, y: pageSize.height - margin + 6))
    }

    private static func drawLabel(_ device: ShelfDevice, in rect: CGRect) {
        NSColor.white.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.fill()
        NSColor(white: 0.82, alpha: 1).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let qrSide = min(rect.height - 20, 96)
        let qrRect = CGRect(
            x: rect.minX + 12, y: rect.minY + (rect.height - qrSide) / 2, width: qrSide, height: qrSide)
        if let tag = device.assetTag,
            let image = QRCode.image(for: DeviceShelfAsset.deepLink(for: tag))
        {
            image.draw(
                in: qrRect, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none])
        }

        let textX = qrRect.maxX + 14
        let textWidth = rect.maxX - 12 - textX
        var y = rect.maxY - 26
        draw(
            device.displayName,
            at: CGPoint(x: textX, y: y), width: textWidth,
            font: .systemFont(ofSize: 11, weight: .semibold), color: .black, lines: 2)
        y -= 30
        draw(
            device.ip, at: CGPoint(x: textX, y: y), width: textWidth,
            font: .monospacedSystemFont(ofSize: 10, weight: .regular), color: .darkGray, lines: 1)
        y -= 16
        if let tag = device.assetTag {
            draw(
                tag, at: CGPoint(x: textX, y: y), width: textWidth,
                font: .monospacedSystemFont(ofSize: 9, weight: .medium), color: .darkGray, lines: 1)
            y -= 14
        }
        let details = [device.location, device.serialNumber.map { "SN \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !details.isEmpty {
            draw(
                details, at: CGPoint(x: textX, y: y), width: textWidth,
                font: .systemFont(ofSize: 8), color: .gray, lines: 2)
        }
    }

    private static func draw(
        _ text: String, at point: CGPoint, width: CGFloat, font: NSFont, color: NSColor, lines: Int
    ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style,
            ])
        attributed.draw(
            with: CGRect(
                x: point.x, y: point.y - CGFloat(lines - 1) * font.pointSize, width: width,
                height: CGFloat(lines) * font.pointSize * 1.2),
            options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }
}
