// Generates the LanFi icon set with CoreGraphics.
//
// Design: navy-to-teal diagonal gradient squircle, a bold white "L" and three
// Wi-Fi arcs. No texture, no stray dots.
//
//   swift scripts/make_icon.swift            # rewrite app icon set + web copies
//   swift scripts/make_icon.swift --preview  # only build/icon-preview.png

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let publicIcons = [
    root.appendingPathComponent("docs/images/lanfi-icon.png"),
    root.appendingPathComponent("site/assets/lanfi-icon.png"),
]

// Canvas is 1024x1024; all geometry below is expressed in that space.
let canvas: CGFloat = 1024
let gradientStart = NSColor(srgbRed: 0x0F / 255, green: 0x24 / 255, blue: 0x40 / 255, alpha: 1)
let gradientMid = NSColor(srgbRed: 0x1E / 255, green: 0x5C / 255, blue: 0x6C / 255, alpha: 1)
let gradientEnd = NSColor(srgbRed: 0x4F / 255, green: 0xC6 / 255, blue: 0xB4 / 255, alpha: 1)

let stem = CGRect(x: 296, y: 300, width: 128, height: 500)   // y from the top
let foot = CGRect(x: 296, y: 672, width: 400, height: 128)
let cornerRadius: CGFloat = 64

let wifiCentre = CGPoint(x: 620, y: 352)
let wifiRadii: [CGFloat] = [86, 152, 218]
let wifiStroke: CGFloat = 38
let wifiDotRadius: CGFloat = 34
let wifiOpacity: [CGFloat] = [1.0, 0.82, 0.64]

/// Tiny raster sizes turn three arcs into mush, so they get one bolder arc.
func compactArtwork() -> ([CGFloat], CGFloat, CGFloat) {
    ([120], 50, 40)
}

func makeIcon(margin: CGFloat, pixels: Int, compact: Bool = false) -> NSBitmapImageRep {
    guard
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { fatalError("Could not create the bitmap context") }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    let scale = CGFloat(pixels) / canvas
    context.scaleBy(x: scale, y: scale)

    // Work in a y-up space: flip vertically so "y" below means "from the top".
    func top(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: canvas - rect.maxY, width: rect.width, height: rect.height)
    }
    func top(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: canvas - point.y) }

    // Squircle background.
    let side = canvas - 2 * margin
    let squircle = CGRect(x: margin, y: margin, width: side, height: side)
    let radius = 230 * side / canvas
    let background = CGPath(
        roundedRect: squircle, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(background)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [gradientStart.cgColor, gradientMid.cgColor, gradientEnd.cgColor] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: squircle.minX, y: squircle.maxY),
        end: CGPoint(x: squircle.maxX, y: squircle.minY),
        options: []
    )
    context.restoreGState()

    // Artwork, scaled with the squircle so the padded app icon keeps proportions.
    context.saveGState()
    context.translateBy(x: margin, y: margin)
    context.scaleBy(x: side / canvas, y: side / canvas)

    context.setFillColor(NSColor.white.cgColor)
    for rect in [stem, foot] {
        context.addPath(
            CGPath(
                roundedRect: top(rect), cornerWidth: cornerRadius,
                cornerHeight: cornerRadius, transform: nil))
    }
    let centre = top(wifiCentre)
    context.addEllipse(
        in: CGRect(
            x: centre.x - wifiDotRadius, y: centre.y - wifiDotRadius,
            width: wifiDotRadius * 2, height: wifiDotRadius * 2))
    context.fillPath()

    let radii = compact ? compactArtwork().0 : wifiRadii
    let stroke = compact ? compactArtwork().1 : wifiStroke
    for (index, radius) in radii.enumerated() {
        let arc = CGMutablePath()
        arc.addArc(
            center: centre, radius: radius,
            startAngle: 45 * .pi / 180, endAngle: 135 * .pi / 180,
            clockwise: false)
        context.setAlpha(wifiOpacity[min(index, wifiOpacity.count - 1)])
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.addPath(arc)
        context.strokePath()
    }
    context.setAlpha(1)
    context.restoreGState()

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image)
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(url.lastPathComponent)")
    }
    try! data.write(to: url)
    print(url.path.replacingOccurrences(of: root.path + "/", with: ""))
}

if CommandLine.arguments.contains("--preview") {
    write(makeIcon(margin: 40, pixels: 1024), to: root.appendingPathComponent("build/icon-preview.png"))
    exit(0)
}

let variants: [(String, Int)] = [
    ("icon_16.png", 16),
    ("icon_16@2x.png", 32),
    ("icon_32.png", 32),
    ("icon_32@2x.png", 64),
    ("icon_128.png", 128),
    ("icon_128@2x.png", 256),
    ("icon_256.png", 256),
    ("icon_256@2x.png", 512),
    ("icon_512.png", 512),
    ("icon_1024.png", 1024),
]

for (name, pixels) in variants {
    write(
        makeIcon(margin: 40, pixels: pixels, compact: pixels <= 64),
        to: iconset.appendingPathComponent(name))
}
for url in publicIcons {
    write(makeIcon(margin: 0, pixels: 1024), to: url)
}
