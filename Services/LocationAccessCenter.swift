import AppKit
import Combine
import CoreLocation
import Foundation

/// The app's single owner of Location Services.
///
/// macOS reveals Wi-Fi names (SSID/BSSID) only to an app with Location access,
/// and most of LanFi depends on that: the analyzer table, the Wi-Fi monitor and
/// its alerts, roaming tests, site surveys and the menu bar. The request and the
/// status check therefore live here, at launch, instead of inside the Wi-Fi
/// analyzer; screens read `state` and call `request()` / `openSystemSettings()`
/// rather than owning a location manager of their own.
@MainActor
final class LocationAccessCenter: NSObject, ObservableObject {
    static let shared = LocationAccessCenter()

    enum AccessState: Equatable, Sendable {
        /// `notDetermined`: macOS has not asked the user yet.
        case undecided
        case granted
        /// Denied or restricted; only System Settings can change it.
        case denied

        var isGranted: Bool { self == .granted }
    }

    @Published private(set) var state: AccessState = .undecided
    /// Drives the app-wide explanation sheet. Settable so a sheet dismissal
    /// writes back to it.
    @Published var isPromptPresented = false
    /// True once `start()` has asked the system at least once.
    @Published private(set) var hasRequested = false

    private let manager = CLLocationManager()
    private var activationObserver: NSObjectProtocol?
    private var didStart = false

    /// Read-only convenience for views that only care whether scanning will
    /// see identifiers.
    var isAuthorized: Bool { state.isGranted }

    override init() {
        super.init()
        manager.delegate = self
        state = Self.state(for: manager.authorizationStatus)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The user may have flipped the switch in System Settings while the
            // app was in the background; re-read instead of trusting the cache.
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    /// Called once from the app's root: asks the system when nobody has decided
    /// yet and shows the explanation sheet when access is missing.
    ///
    /// Idempotent, so a rebuilt root view does not ask again or re-open a sheet
    /// the user already dismissed.
    func start() {
        guard !didStart else {
            refresh()
            return
        }
        didStart = true
        refresh()
        if state == .undecided {
            hasRequested = true
            manager.requestWhenInUseAuthorization()
        }
        if !state.isGranted {
            isPromptPresented = true
        }
    }

    /// The explicit action behind every "Allow Access" button.
    func request() {
        refresh()
        hasRequested = true
        switch state {
        case .undecided:
            manager.requestWhenInUseAuthorization()
        case .granted:
            break
        case .denied:
            // A second request is ignored by macOS; send the user where the
            // switch actually is.
            openSystemSettings()
        }
    }

    func refresh() {
        state = Self.state(for: manager.authorizationStatus)
    }

    func presentPrompt() {
        refresh()
        isPromptPresented = true
    }

    func dismissPrompt() {
        isPromptPresented = false
    }

    func openSystemSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Maps CoreLocation's five delegates' states onto the three the app shows.
    static func state(for status: CLAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized, .authorizedAlways: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undecided
        @unknown default: return .undecided
        }
    }

    fileprivate func apply(_ status: CLAuthorizationStatus) {
        state = Self.state(for: status)
        if state.isGranted {
            isPromptPresented = false
        }
    }
}

extension LocationAccessCenter: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.apply(status) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
    ) {
        Task { @MainActor [weak self] in self?.apply(status) }
    }
}
