import Foundation
import UserNotifications

/// Notification seam: the monitor raises events through this protocol so its
/// tests do not need `UNUserNotificationCenter`.
@MainActor
protocol MonitorNotifying: AnyObject {
    func notify(_ event: MonitorEvent, settings: MonitorAlertSettings)
    func requestAuthorization() async -> Bool
}

/// Plain banner posting for surfaces outside the monitor (the connectivity
/// watchdog). The notifier is the one `UNUserNotificationCenter` delegate, so
/// every screen posts through it instead of installing a second one.
@MainActor
protocol ConnectivityNotifying: AnyObject {
    func post(title: String, body: String, identifier: String)
}

@MainActor
final class MonitorNotifier: NSObject, MonitorNotifying, ConnectivityNotifying,
    UNUserNotificationCenterDelegate
{
    /// Shared so the monitor and the connectivity watchdog do not each install
    /// a delegate on the notification center.
    static let shared = MonitorNotifier()

    private let center = UNUserNotificationCenter.current()
    private var policy = MonitorAlertPolicy()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Show the banner even while LanFi is frontmost; otherwise macOS silently
    /// drops the alert and the feature looks broken.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func post(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: nil)
        Task { try? await center.add(request) }
    }

    func notify(_ event: MonitorEvent, settings: MonitorAlertSettings) {
        guard policy.shouldNotify(event: event, settings: settings) else { return }

        let content = UNMutableNotificationContent()
        content.title = "LanFi · \(event.kind.title)"
        content.body = "\(event.ssid): \(event.detail)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.id.uuidString, content: content, trigger: nil)
        Task { try? await center.add(request) }
    }
}
