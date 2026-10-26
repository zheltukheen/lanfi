import AppKit
import Foundation

struct ColoringRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var field: NetworkFilterField
    var op: NetworkFilterOperator
    var value: String
    var colorHex: String
    var isEnabled: Bool = true
}

final class ColoringRuleStore {
    private let defaults: UserDefaults
    private let key = "Wifa.coloringRules"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [ColoringRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ColoringRule].self, from: data)) ?? []
    }

    func save(_ rules: [ColoringRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }
}

enum ColorHex {
    static func color(from hex: String) -> NSColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let r, g, b, a: Double
        if value.count == 6 {
            r = Double((number >> 16) & 0xFF) / 255
            g = Double((number >> 8) & 0xFF) / 255
            b = Double(number & 0xFF) / 255
            a = 1
        } else {
            r = Double((number >> 24) & 0xFF) / 255
            g = Double((number >> 16) & 0xFF) / 255
            b = Double((number >> 8) & 0xFF) / 255
            a = Double(number & 0xFF) / 255
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func hex(from color: NSColor) -> String {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X",
            Int(round(converted.redComponent * 255)),
            Int(round(converted.greenComponent * 255)),
            Int(round(converted.blueComponent * 255))
        )
    }
}
