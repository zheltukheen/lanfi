import Foundation

/// Rolling samples for the signal, noise, SNR and utilization charts.
///
/// The value is a plain struct so the view model can accumulate a whole scan
/// and publish it once instead of invalidating SwiftUI for every network.
struct NetworkHistory: Equatable {
    private(set) var signal: [String: [Int]] = [:]
    private(set) var noise: [String: [Int?]] = [:]
    private(set) var snr: [String: [Int?]] = [:]
    private(set) var utilization: [String: [Int?]] = [:]

    mutating func record(_ network: NetworkModel, maxPoints: Int) {
        let limit = max(1, maxPoints)
        signal[network.id] = Self.appended(network.signal, to: signal[network.id] ?? [], limit: limit)
        noise[network.id] = Self.appended(network.noise, to: noise[network.id] ?? [], limit: limit)
        snr[network.id] = Self.appended(network.snr, to: snr[network.id] ?? [], limit: limit)
        utilization[network.id] = Self.appended(
            network.channelUtilization, to: utilization[network.id] ?? [], limit: limit)
    }

    mutating func remove(_ id: String) {
        signal.removeValue(forKey: id)
        noise.removeValue(forKey: id)
        snr.removeValue(forKey: id)
        utilization.removeValue(forKey: id)
    }

    mutating func removeAll() {
        signal.removeAll()
        noise.removeAll()
        snr.removeAll()
        utilization.removeAll()
    }

    func signalStatistics(for id: String) -> HistoryStatistics? {
        HistoryStatistics(values: signal[id] ?? [])
    }

    func utilizationStatistics(for id: String) -> HistoryStatistics? {
        HistoryStatistics(values: (utilization[id] ?? []).compactMap { $0 })
    }

    private static func appended<T>(_ value: T, to values: [T], limit: Int) -> [T] {
        var updated = values
        updated.append(value)
        if updated.count > limit {
            updated.removeFirst(updated.count - limit)
        }
        return updated
    }
}
