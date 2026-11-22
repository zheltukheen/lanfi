import Foundation

/// P2 — every protocol decode carries the draft it was written against, so a
/// capture analysed months apart can be compared honestly. LanFi decodes
/// 802.11be/EHT today; 802.11bn (UHR) is tracked as a draft, not claimed as
/// decoded.
struct ProtocolDecoderVersion: Equatable, Comparable {
    let standard: String
    let draft: String
    let decoder: String

    static let current = ProtocolDecoderVersion(
        standard: "802.11bn", draft: "D1.4", decoder: "LanFi 1")

    var shortLabel: String { "\(standard) \(draft) · decoder \(decoder)" }

    /// Shown in the protocol inspector only when the network is Wi-Fi 7, the
    /// newest generation with a published decoder.
    static func note(for generation: WiFiStandard) -> String? {
        switch generation {
        case .mode11be:
            return "Decoded as 802.11be/EHT; \(current.standard) \(current.draft) is not decoded yet."
        default:
            return nil
        }
    }

    static func < (left: ProtocolDecoderVersion, right: ProtocolDecoderVersion) -> Bool {
        (left.standard, left.draft, left.decoder) < (right.standard, right.draft, right.decoder)
    }
}
