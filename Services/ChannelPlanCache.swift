import Foundation

/// Controller-reported channel plans, keyed by AP MAC. Populated by the
/// Controllers settings window and consumed by the channel advisor.
enum ChannelPlanCache {
    private static let lock = NSLock()
    private static var plans: [String: [Int]] = [:]

    static func update(mac: String, channels: [Int]) {
        let key = mac.uppercased()
        guard !key.isEmpty else { return }
        lock.lock()
        if channels.isEmpty {
            plans.removeValue(forKey: key)
        } else {
            plans[key] = channels.sorted()
        }
        lock.unlock()
    }

    static func channels(for mac: String) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return plans[mac.uppercased()] ?? []
    }
}
