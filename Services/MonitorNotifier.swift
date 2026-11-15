import Foundation
import UserNotifications

@MainActor
final class MonitorNotifier {
    private let center = UNUserNotificationCenter.current()
    private var policy = MonitorAlertPolicy()

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
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
