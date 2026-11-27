import Combine
import CoreLocation
import Foundation

/// One-shot location for GPS-tagged survey points. macOS has no GPS on most
/// Macs, so this is Wi-Fi based and deliberately low precision; the map view
/// says so instead of implying survey-grade accuracy.
///
/// This type only reads a fix; the permission itself is asked for by
/// `LocationAccessCenter`, the app's single location module, so a map view can
/// never trigger a second system prompt on its own.
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: GeoPoint?
    @Published private(set) var statusDescription = String(localized: "Location not requested")
    @Published private(set) var isRequesting = false

    private let manager = CLLocationManager()
    private var accessCancellable: AnyCancellable?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    @Published private(set) var errorMessage: String?

    /// Asks for a fix. Without permission it shows the shared explanation sheet
    /// and continues by itself once LocationAccessCenter reports access.
    func request() {
        Task { @MainActor [weak self] in self?.beginRequest() }
    }

    @MainActor
    private func beginRequest() {
        errorMessage = nil
        let access = LocationAccessCenter.shared
        access.refresh()
        guard access.state.isGranted else {
            isRequesting = false
            statusDescription =
                access.state == .denied
                ? String(localized: "Location denied — enable it in Settings")
                : String(localized: "Waiting for location permission")
            accessCancellable = access.$state
                .filter { $0.isGranted }
                .first()
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.requestSystemFix() }
                }
            access.presentPrompt()
            return
        }
        requestSystemFix()
    }

    @MainActor
    private func requestSystemFix() {
        accessCancellable = nil
        isRequesting = true
        manager.requestLocation()
    }

    // CLLocationManager delivers these on the run loop where it was created,
    // but the protocol is nonisolated. Publish on main explicitly.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let point = GeoPoint(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let accuracy = location.horizontalAccuracy
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            coordinate = point
            isRequesting = false
            statusDescription = String(
                format: String(localized: "±%.0f m accuracy"), accuracy)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let isUnknown = (error as? CLError)?.code == .locationUnknown
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRequesting = false
            if isUnknown {
                statusDescription = String(localized: "Location is temporarily unavailable")
                return
            }
            errorMessage = error.localizedDescription
            statusDescription = String(localized: "Location failed")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch status {
            case .authorized, .authorizedAlways:
                statusDescription = String(localized: "Location allowed")
            case .denied, .restricted:
                statusDescription = String(localized: "Location denied — enable it in Settings")
            default:
                statusDescription = String(localized: "Waiting for location permission")
            }
        }
    }
}
