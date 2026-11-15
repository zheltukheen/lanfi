import Foundation

/// Chooses the scan interval for the current app state.
///
/// The base interval is what the user picked. When the app is in the
/// background or macOS is in Low Power Mode the interval grows so a long
/// monitoring session does not drain the battery with a scan every 3 seconds.
struct ScanCadence: Equatable {
    let baseInterval: TimeInterval
    let reduceInBackground: Bool
    let lowPowerMode: Bool

    func interval(isForeground: Bool) -> TimeInterval {
        guard reduceInBackground else { return baseInterval }
        var interval = max(1, baseInterval)
        if !isForeground {
            interval = max(interval, 15)
        }
        if lowPowerMode {
            interval = max(interval, 30)
        }
        return min(interval, 300)
    }
}
