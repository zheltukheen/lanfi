import Foundation

enum SignalDisplayMode: String, CaseIterable, Identifiable {
    case dbm = "dBm"
    case percent = "%"
    var id: String { rawValue }
}
