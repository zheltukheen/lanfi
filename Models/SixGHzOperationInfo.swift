import Foundation

/// The 6 GHz Operation Information field of the HE Operation element.
///
/// Five octets: primary channel, a control octet (width 2 bits, duplicate
/// beacon 1 bit, regulatory info 3 bits), CCFS0, CCFS1 and the minimum rate.
/// Regulatory Info carries the AP's power mode; it is regulatory-domain
/// dependent, so the labels here follow the US/FCC meaning used by Wireshark.
struct SixGHzOperationInfo: Equatable {
    enum PowerMode: String, Equatable {
        case lowPowerIndoor
        case standardPower
        case veryLowPower
        case other

        var shortLabel: String {
            switch self {
            case .lowPowerIndoor: return "LPI"
            case .standardPower: return "SP"
            case .veryLowPower: return "VLP"
            case .other: return "Other"
            }
        }

        var title: String {
            switch self {
            case .lowPowerIndoor: return String(localized: "Low Power Indoor (LPI)")
            case .standardPower: return String(localized: "Standard Power (SP)")
            case .veryLowPower: return String(localized: "Very Low Power (VLP)")
            case .other: return String(localized: "Other regulatory mode")
            }
        }
    }

    let primaryChannel: Int
    let widthMHz: Int
    let duplicateBeacon: Bool
    let regulatoryInfo: Int
    let centerFrequency0: Int
    let centerFrequency1: Int
    let minimumRate: Int

    var powerMode: PowerMode {
        switch regulatoryInfo {
        case 0: return .lowPowerIndoor
        case 1: return .standardPower
        case 2: return .veryLowPower
        default: return .other
        }
    }

    var summary: String {
        "6 GHz \(powerMode.shortLabel) · ch \(primaryChannel) · \(widthMHz) MHz"
    }

    var detailLines: [String] {
        [
            "6 GHz power mode: \(powerMode.title) (Regulatory Info \(regulatoryInfo))",
            "6 GHz primary channel: \(primaryChannel), width \(widthMHz) MHz",
            "6 GHz center frequency segment 0: \(centerFrequency0), segment 1: \(centerFrequency1)",
            "6 GHz minimum rate: \(minimumRate)",
            "6 GHz duplicate beacon: \(duplicateBeacon ? "Yes" : "No")",
        ]
    }

    /// `data` is the HE Operation element payload **after** the extension ID.
    static func parse(heOperationPayload data: Data) -> SixGHzOperationInfo? {
        guard data.count >= 6 else { return nil }
        let parameters =
            UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16)
        let hasVHTOperation = (parameters & (1 << 10)) != 0
        let hasCoHostedBSS = (parameters & (1 << 11)) != 0
        let hasSixGHz = (parameters & (1 << 13)) != 0
        guard hasSixGHz else { return nil }

        // HE Operation Parameters (3) + BSS Color Info (1) + Basic HE-MCS (2).
        var offset = 6
        if hasVHTOperation { offset += 3 }
        if hasCoHostedBSS { offset += 1 }
        guard offset + 5 <= data.count else { return nil }

        let primary = Int(data[offset])
        let control = data[offset + 1]
        let widthBits = Int(control & 0x03)
        let widthMHz: Int
        switch widthBits {
        case 0: widthMHz = 20
        case 1: widthMHz = 40
        case 2: widthMHz = 80
        default: widthMHz = 160
        }
        return SixGHzOperationInfo(
            primaryChannel: primary,
            widthMHz: widthMHz,
            duplicateBeacon: (control & 0x04) != 0,
            regulatoryInfo: Int((control >> 3) & 0x07),
            centerFrequency0: Int(data[offset + 2]),
            centerFrequency1: Int(data[offset + 3]),
            minimumRate: Int(data[offset + 4])
        )
    }

    /// Convenience for the UI, where an element is stored as hex plus the
    /// extension ID byte (255+36).
    static func parse(elementRawHex hex: String) -> SixGHzOperationInfo? {
        guard let data = Data(elementHex: hex), data.first == 36 else { return nil }
        return parse(heOperationPayload: Data(data.dropFirst()))
    }
}

extension Data {
    /// Parses whitespace-separated hex bytes ("FF 01 3C"), ignoring any
    /// truncation ellipsis the element view adds.
    init?(elementHex: String) {
        let tokens = elementHex.split(whereSeparator: { $0 == " " || $0 == "\n" })
        var bytes: [UInt8] = []
        for token in tokens {
            guard token.count == 2, let byte = UInt8(token, radix: 16) else { return nil }
            bytes.append(byte)
        }
        guard !bytes.isEmpty else { return nil }
        self = Data(bytes)
    }
}
