import Foundation

struct SupportedChannel: Identifiable, Hashable {
    let band: WiFiBand
    let channel: Int

    var id: String { "\(band.rawValue)-\(channel)" }
}
