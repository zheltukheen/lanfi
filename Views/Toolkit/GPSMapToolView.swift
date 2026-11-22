import AppKit
import MapKit
import SwiftUI

/// P1.9: pin the networks seen during an opt-in GPS walk on a real map.
/// Open networks are green, secured ones red; the strongest observation per
/// BSSID wins, and each walk is saved as a named trip that can be reopened or
/// exported as GeoJSON/CSV. macOS location is Wi-Fi-derived and approximate.
struct GPSMapToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel
    @StateObject private var recorder = GPSTripRecorder()
    @StateObject private var location = CurrentLocationProvider()
    @State private var tripName = ""
    @State private var message: String?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.card) {
                controls
                map
                summary
                pinsTable
                tripsCard
                Text(
                    "Location is used only while a trip is recording, stays on this Mac, and is never attached to the live scan or sent anywhere. macOS derives it from Wi-Fi, so expect street-level accuracy, not survey-grade."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(DesignToken.Spacing.section)
        }
        .onAppear {
            recorder.networks = { [weak analyzer] in analyzer?.networks ?? [] }
            recorder.location = { [weak location] in location?.coordinate }
            // Do not ask for Location on appear: the user starts a trip or
            // presses Locate, so the system prompt has a visible reason.
        }
        .onChange(of: location.coordinate) { point in
            if point != nil, recorder.isRecording, recorder.displayedTrip?.pins.isEmpty ?? true {
                recorder.sampleNow()
            }
        }
    }

    private var controls: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            TextField("Trip name", text: $tripName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            if recorder.isRecording {
                Button {
                    recorder.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.danger)
            } else {
                Button {
                    location.request()
                    recorder.start(name: tripName)
                    tripName = ""
                } label: {
                    Label("Start trip", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                location.request()
            } label: {
                Label("Locate", systemImage: "location")
            }
            .disabled(location.isRequesting)
            Spacer()
            Menu {
                Button("GeoJSON…") { export(.geoJSON) }
                Button("CSV…") { export(.csv) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(recorder.displayedTrip == nil)
        }
        .appCardSurface()
        .padding(DesignToken.Spacing.medium)
    }

    private var map: some View {
        GPSNetworkMap(trip: recorder.displayedTrip, current: location.coordinate)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.card)
                    .strokeBorder(Theme.Surface.cardStroke, lineWidth: Theme.Stroke.hairline)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("GPS network map")
            .accessibilityValue(
                Text(
                    "\(recorder.displayedTrip?.pins.count ?? 0) pinned networks, \(recorder.displayedTrip?.openCount ?? 0) open"
                ))
    }

    private var summary: some View {
        HStack(spacing: DesignToken.Spacing.large) {
            StatTile(
                value: "\(recorder.displayedTrip?.pins.count ?? 0)", label: "Networks")
            StatTile(
                value: "\(recorder.displayedTrip?.openCount ?? 0)", label: "Open")
            StatTile(
                value: "\(recorder.displayedTrip?.securedCount ?? 0)", label: "Secured")
            StatTile(
                value: String(format: "%.0f m", GeoMath.spanMeters(recorder.displayedTrip?.track ?? [])),
                label: "Walk")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(location.statusDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(recorder.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var pinsTable: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            ToolkitSectionLabel(text: "Pinned networks")
            let pins = recorder.displayedTrip?.pins ?? []
            if pins.isEmpty {
                Text("Start a trip and walk the area; each network is pinned at its strongest position.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(DesignToken.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCardSurface()
            } else {
                AppTable(
                    columns: columns, rows: pins, initialKey: "rssi", ascending: false
                )
                .frame(height: min(420, CGFloat(pins.count) * 34 + 44))
                .appCardSurface()
            }
        }
    }

    private var columns: [AppTableColumn<GPSNetworkPin>] {
        [
            AppTableColumn(id: "ssid", title: "SSID", minWidth: 140) {
                .text($0.ssid)
            } cell: {
                Text($0.ssid.isEmpty ? "—" : $0.ssid).lineLimit(1)
            },
            AppTableColumn(id: "bssid", title: "BSSID", minWidth: 140) {
                .text($0.bssid)
            } cell: {
                Text($0.bssid).font(.caption.monospaced()).foregroundColor(.secondary)
            },
            AppTableColumn(id: "rssi", title: "Signal", minWidth: 70) {
                .number(Double($0.rssi))
            } cell: {
                Text("\($0.rssi) dBm").font(.caption.monospacedDigit())
            },
            AppTableColumn(id: "security", title: "Security", minWidth: 80, isSortable: false) {
                .text($0.isOpen ? "open" : "secured")
            } cell: {
                StatusPill(
                    text: $0.isOpen ? "Open" : "Secured",
                    tone: $0.isOpen ? .good : .bad)
            },
            AppTableColumn(id: "band", title: "Band", minWidth: 70) {
                .text($0.band)
            } cell: {
                Text($0.band).font(.caption)
            },
            AppTableColumn(id: "channel", title: "Channel", minWidth: 70) {
                .number(Double($0.channel))
            } cell: {
                Text("\($0.channel)").font(.caption.monospacedDigit())
            },
        ]
    }

    private var tripsCard: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack {
                ToolkitSectionLabel(text: "Saved trips")
                Spacer()
                if let trip = recorder.displayedTrip {
                    Button(role: .destructive) {
                        recorder.delete(trip.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if recorder.trips.isEmpty {
                Text("No trips saved yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(recorder.trips.sorted { $0.startedAt > $1.startedAt }) { trip in
                    Button {
                        recorder.select(trip.id)
                    } label: {
                        HStack(spacing: DesignToken.Spacing.small) {
                            Image(
                                systemName: trip.id == recorder.displayedTrip?.id
                                    ? "largecircle.fill.circle" : "circle"
                            )
                            .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(trip.name).font(.callout)
                                Text(
                                    "\(trip.pins.count) networks · \(String(format: "%.0f m", GeoMath.spanMeters(trip.track))) · \(trip.startedAt.formatted(date: .abbreviated, time: .shortened))"
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            if trip.isRecording {
                                StatusPill(text: "Recording", tone: .warning)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .accessibilityLabel(
                        "\(trip.name), \(trip.pins.count) networks")
                }
            }
            if let message {
                Text(message).font(.caption2).foregroundColor(.secondary)
            }
            if let error = exportError {
                Text(error).font(.caption2).foregroundColor(AppPalette.danger)
            }
        }
        .padding(DesignToken.Spacing.medium)
        .appCardSurface()
    }

    private enum ExportKind { case geoJSON, csv }

    private func export(_ kind: ExportKind) {
        guard let trip = recorder.displayedTrip else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            "\(trip.name.replacingOccurrences(of: "/", with: "-")).\(kind == .geoJSON ? "geojson" : "csv")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = kind == .geoJSON ? GPSTripExport.geoJSON(trip) : GPSTripExport.csv(trip)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            message = String(localized: "Exported \(trip.pins.count) networks.")
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - Map

private struct GPSNetworkMap: NSViewRepresentable {
    let trip: GPSTrip?
    let current: GeoPoint?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        let signature = "\(trip?.id.uuidString ?? "none")-\(trip?.pins.count ?? 0)-\(current?.latitude ?? 0)"
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature

        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)
        guard let trip else { return }

        for pin in trip.pins {
            map.addAnnotation(GPSPinAnnotation(pin: pin))
        }
        if trip.track.count > 1 {
            var coordinates = trip.track.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            map.addOverlay(MKPolyline(coordinates: &coordinates, count: coordinates.count))
        }
        if let current {
            map.addAnnotation(
                CurrentPositionAnnotation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: current.latitude, longitude: current.longitude)))
        }
        let points =
            trip.pins.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            + trip.track.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        map.setVisibleMapRect(
            mapRect(for: points),
            edgePadding: NSEdgeInsets(
                top: 40, left: 40, bottom: 40, right: 40), animated: false)
    }

    private func mapRect(for points: [CLLocationCoordinate2D]) -> MKMapRect {
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(point)
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
        }
        guard !rect.isNull else {
            return MKMapRect(
                x: MKMapPoint(CLLocationCoordinate2D(latitude: 51.5075, longitude: -0.1278)).x,
                y: MKMapPoint(CLLocationCoordinate2D(latitude: 51.5075, longitude: -0.1278)).y,
                width: 1_000, height: 1_000)
        }
        return rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var signature = ""

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is CurrentPositionAnnotation {
                let identifier = "current"
                let view =
                    mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.markerTintColor = .systemBlue
                view.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)
                view.annotation = annotation
                return view
            }
            guard let pin = annotation as? GPSPinAnnotation else { return nil }
            let identifier = "network"
            let view =
                mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = NSColor(pin.pin.isOpen ? AppPalette.ok : AppPalette.danger)
            view.glyphImage = NSImage(
                systemSymbolName: pin.pin.isOpen ? "lock.open" : "lock",
                accessibilityDescription: pin.pin.isOpen ? "Open network" : "Secured network")
            view.titleVisibility = .adaptive
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .secondaryLabelColor
            renderer.lineWidth = 2
            renderer.lineDashPattern = [4, 4]
            return renderer
        }
    }
}

private final class GPSPinAnnotation: NSObject, MKAnnotation {
    let pin: GPSNetworkPin
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
    }
    var title: String? { pin.ssid.isEmpty ? pin.bssid : pin.ssid }
    var subtitle: String? {
        "\(pin.rssi) dBm · \(pin.isOpen ? "open" : "secured") · \(pin.band) ch \(pin.channel)"
    }

    init(pin: GPSNetworkPin) {
        self.pin = pin
    }
}

private final class CurrentPositionAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var title: String? { String(localized: "You") }

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}
