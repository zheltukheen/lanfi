import Foundation

/// Preamble puncturing state decoded from the EHT Operation element
/// (802.11be). The Disabled Subchannel Bitmap marks 20 MHz subchannels the
/// AP avoids because of interference; bit 0 is the lowest-frequency
/// subchannel within the BSS bandwidth.
struct EHTPuncturing: Equatable {
    let widthCode: Int
    let bitmapPresent: Bool
    /// Punctured subchannels, 1-based, counting up from the lowest frequency.
    let puncturedSubchannels: [Int]
    let validSubchannelCount: Int

    static let subchannelsPerWidth = [1, 2, 4, 8, 16]

    static func parse(elements: [InformationElement]) -> EHTPuncturing? {
        guard
            let element = elements.first(where: { $0.name.lowercased().contains("eht operation") })
        else { return nil }

        var widthCode = 0
        var bitmapPresent = false
        var sawPuncturedLine = false
        var punctured: [Int] = []
        var validCount = 0

        for line in element.detailLines {
            if line.hasPrefix("EHT Operation parameters: 0x"), line.count >= 28 {
                let hex = line.dropLast().suffix(2)
                if let params = UInt8(hex, radix: 16) {
                    bitmapPresent = params & 0x02 != 0
                }
            } else if line.hasPrefix("EHT Operation channel width ") {
                // Longest names first: "320 MHz" contains "20 MHz" as a substring.
                let names: [(String, Int)] = [
                    ("320 MHz", 4), ("160 MHz", 3), ("80 MHz", 2), ("40 MHz", 1), ("20 MHz", 0),
                ]
                for (name, code) in names where line.contains(name) {
                    widthCode = code
                    validCount = subchannelsPerWidth[code]
                    break
                }
            } else if line.hasPrefix("Punctured subchannels: ") {
                sawPuncturedLine = true
                let body = line.dropFirst("Punctured subchannels: ".count)
                if let range = body.range(of: " (of ") {
                    punctured = body[..<range.lowerBound]
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                }
            }
        }

        if validCount == 0 { validCount = subchannelsPerWidth[widthCode] }
        return EHTPuncturing(
            widthCode: widthCode,
            bitmapPresent: bitmapPresent || sawPuncturedLine,
            puncturedSubchannels: punctured,
            validSubchannelCount: validCount
        )
    }

    /// Short cell text: punctured positions, "None" when the bitmap is
    /// present but empty, "-" when the element carries no bitmap.
    var columnLabel: String {
        guard bitmapPresent else { return "-" }
        return puncturedSubchannels.isEmpty ? "None" : puncturedSubchannels.map(String.init).joined(separator: ", ")
    }
}
