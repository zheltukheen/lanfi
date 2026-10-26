import Foundation

struct FilterProfile: Codable, Equatable {
    var version: Int = 1
    var name: String
    var searchText: String
    var band24: Bool
    var band5: Bool
    var band6: Bool
    var minSignal: Double
    var groupMode: String
    var signalUnit: String

    static func capture(
        name: String,
        searchText: String,
        band24: Bool,
        band5: Bool,
        band6: Bool,
        minSignal: Double,
        groupMode: NetworkGroupMode,
        signalUnit: SignalDisplayMode
    ) -> FilterProfile {
        FilterProfile(
            name: name.isEmpty ? "LanFi filter" : name,
            searchText: searchText,
            band24: band24,
            band5: band5,
            band6: band6,
            minSignal: minSignal,
            groupMode: groupMode.rawValue,
            signalUnit: signalUnit.rawValue
        )
    }
}
