import Foundation

/// Drives an opt-in GPS walk: while recording, every few seconds it pairs the
/// current location with the live scan and keeps the strongest pin per BSSID.
/// Nothing is recorded until the user presses Start.
@MainActor
final class GPSTripRecorder: ObservableObject {
    @Published private(set) var trips: [GPSTrip] = []
    @Published private(set) var activeTripID: UUID?
    @Published var selectedTripID: UUID?
    @Published private(set) var isRecording = false
    @Published private(set) var statusMessage = String(
        localized: "Idle. Nothing is recorded until you start a trip.")

    /// Injected by the screen: the live scan and the current location. Keeping
    /// them as closures makes the recorder testable without CoreWLAN or
    /// CoreLocation.
    var networks: () -> [NetworkModel] = { [] }
    var location: () -> GeoPoint? = { nil }

    private let store: GPSTripStore
    private var timer: Timer?
    private let sampleInterval: TimeInterval

    init(store: GPSTripStore = GPSTripStore(), sampleInterval: TimeInterval = 3) {
        self.store = store
        self.sampleInterval = sampleInterval
        trips = store.load()
        selectedTripID = trips.last?.id
    }

    var activeTrip: GPSTrip? {
        trips.first { $0.id == activeTripID }
    }

    /// The trip the map draws: the selected one, else the live one, else the
    /// newest saved trip.
    var displayedTrip: GPSTrip? {
        if let selectedTripID, let trip = trips.first(where: { $0.id == selectedTripID }) {
            return trip
        }
        return activeTrip ?? trips.last
    }

    func start(name: String) {
        guard !isRecording else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trip = GPSTrip(
            name: trimmed.isEmpty
                ? String(
                    format: String(localized: "Trip %@"),
                    Date().formatted(date: .abbreviated, time: .shortened))
                : trimmed)
        trips.append(trip)
        activeTripID = trip.id
        selectedTripID = trip.id
        isRecording = true
        statusMessage = String(localized: "Recording. Walk the area at a normal pace.")
        sampleNow()
        let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard let id = activeTripID else { return }
        timer?.invalidate()
        timer = nil
        if let index = trips.firstIndex(where: { $0.id == id }) {
            trips[index].endedAt = Date()
        }
        activeTripID = nil
        isRecording = false
        save()
        statusMessage = String(
            format: String(localized: "Stopped. %lld networks pinned."),
            trips.first(where: { $0.id == id })?.pins.count ?? 0)
    }

    /// One sample at the current location. Public so the screen can take a
    /// point on demand and so tests can drive it without a timer.
    func sampleNow() {
        guard let id = activeTripID,
            let index = trips.firstIndex(where: { $0.id == id }),
            let point = location()
        else { return }
        let scan = networks()
        for network in scan where !network.bssid.isEmpty {
            let security = network.security.lowercased()
            trips[index].record(
                bssid: network.bssid, ssid: network.displaySSID,
                rssi: network.signal,
                isOpen: security.contains("open") || security.contains("none"),
                band: network.band.label, channel: network.channel, at: point)
        }
        if !scan.isEmpty {
            statusMessage = String(
                format: String(localized: "Recording · %lld networks · %lld track points"),
                trips[index].pins.count, trips[index].track.count)
        }
        save()
    }

    func delete(_ id: UUID) {
        if id == activeTripID {
            stop()
        }
        trips.removeAll { $0.id == id }
        if selectedTripID == id {
            selectedTripID = trips.last?.id
        }
        save()
    }

    func select(_ id: UUID?) {
        selectedTripID = id
    }

    func save() {
        try? store.save(trips)
    }
}
