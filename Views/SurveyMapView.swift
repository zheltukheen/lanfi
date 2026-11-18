import AppKit
import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// P1.9: GPS-tagged survey walks. The track is drawn as a real MapKit polyline
/// (not just points), so an imported GPX reads as a route. macOS location is
/// Wi-Fi-derived on most Macs, so the copy says it is approximate.
struct SurveyMapSheet: View {
    @ObservedObject var survey: SurveyViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var location = CurrentLocationProvider()
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            AppSheetHeader(
                icon: "map",
                title: "Survey map",
                subtitle:
                    "GPX walks and GPS-tagged samples on one map. macOS location is approximate; use it for orientation, not certification."
            ) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            SurveyTrackMap(
                track: survey.gpsTrack,
                samples: survey.samples,
                current: location.coordinate
            )
            .frame(minHeight: 360)
            .accessibilityLabel(Text("Survey map"))
            .accessibilityValue(
                Text(
                    "\(survey.gpsTrack.count) track points, \(survey.samples.filter { $0.latitude != nil }.count) tagged samples"
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.card)
                    .strokeBorder(Color.primary.opacity(0.08))
            )

            HStack(spacing: DesignToken.Spacing.small) {
                Button {
                    importGPX()
                } label: {
                    Label("Import GPX…", systemImage: "square.and.arrow.down")
                }
                Button {
                    loadSampleTrack()
                } label: {
                    Label("Load Sample Walk", systemImage: "figure.walk.motion")
                }
                Button {
                    exportGPX()
                } label: {
                    Label("Export GPX…", systemImage: "square.and.arrow.up")
                }
                .disabled(survey.gpsTrack.isEmpty)
                Button {
                    location.request()
                } label: {
                    Label("Locate Me", systemImage: "location")
                }
                .disabled(location.isRequesting)
                Button {
                    tagLastSample()
                } label: {
                    Label("Tag Last Sample", systemImage: "mappin.and.ellipse")
                }
                .disabled(survey.samples.isEmpty || location.coordinate == nil)
                Spacer()
                Text(location.statusDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: DesignToken.Spacing.large) {
                StatTile(value: "\(survey.gpsTrack.count)", label: "Track points")
                StatTile(
                    value: String(format: "%.0f m", GeoMath.spanMeters(survey.gpsTrack)),
                    label: "Walk length")
                StatTile(
                    value: "\(survey.samples.filter { $0.latitude != nil }.count)",
                    label: "Tagged samples")
                Spacer()
            }

            if let message {
                Text(message).font(.caption).foregroundColor(.secondary)
            }
            if let error = location.errorMessage {
                Text(error).font(.caption).foregroundColor(AppPalette.danger)
            }
        }
        .appSheet(width: DesignToken.Layout.sheetWidthWide, minHeight: 560)
    }

    private func tagLastSample() {
        guard let coordinate = location.coordinate else {
            message = String(localized: "Request the current location first.")
            return
        }
        survey.tagLastSample(latitude: coordinate.latitude, longitude: coordinate.longitude)
        message = String(localized: "Tagged the newest sample with the current position.")
    }

    private func loadSampleTrack() {
        let points: [GeoPoint]
        if let url = Bundle.main.url(forResource: "lanfi-office-walk", withExtension: "gpx"),
            let data = try? Data(contentsOf: url)
        {
            points = GPXCodec.parse(data: data)
        } else {
            points = GPXCodec.demoTrack()
        }
        survey.setGPSTrack(points)
        message = String(
            format: String(localized: "Loaded a sample walk with %lld points."), points.count)
    }

    private func importGPX() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import GPX track")
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url)
        else { return }
        let points = GPXCodec.parse(data: data)
        guard !points.isEmpty else {
            message = String(localized: "No track points found in that file.")
            return
        }
        survey.setGPSTrack(points)
        message = String(
            format: String(localized: "Imported %lld points."), points.count)
    }

    private func exportGPX() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export GPX track")
        panel.nameFieldStringValue = "LanFi-survey.gpx"
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let document = GPXCodec.document(points: survey.gpsTrack, name: survey.project.name)
        try? document.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// MapKit bridge that draws the GPX track as a polyline plus coloured sample
/// and current-location markers. SwiftUI's macOS 13 `Map` cannot render an
/// overlay line, which is why this screen owns a small `MKMapView`.
struct SurveyTrackMap: NSViewRepresentable {
    let track: [GeoPoint]
    let samples: [SurveySample]
    let current: GeoPoint?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.showsCompass = false
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.update(track: track, samples: samples, current: current, map: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var signature = ""

        func update(track: [GeoPoint], samples: [SurveySample], current: GeoPoint?, map: MKMapView) {
            let located = samples.compactMap { sample -> (SurveySample, GeoPoint)? in
                guard let latitude = sample.latitude, let longitude = sample.longitude else {
                    return nil
                }
                return (sample, GeoPoint(latitude: latitude, longitude: longitude))
            }
            let trackKey = track.reduce(0.0) { $0 + $1.latitude + $1.longitude }
            let nextSignature =
                "\(track.count)|\(trackKey)|\(located.count)|\(located.last?.0.rssi ?? 0)"
                + "|\(current?.latitude ?? 0)|\(current?.longitude ?? 0)"
            guard nextSignature != signature else { return }
            signature = nextSignature

            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)

            if track.count >= 2 {
                let coordinates = track.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                map.addOverlay(polyline)
            }

            var points = track
            for (sample, coordinate) in located {
                points.append(coordinate)
                let annotation = SurveyMapAnnotation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: coordinate.latitude, longitude: coordinate.longitude),
                    title: "\(sample.rssi) dBm · \(sample.ssid)",
                    tint: Self.color(for: sample.rssi))
                map.addAnnotation(annotation)
            }
            if let current {
                let annotation = SurveyMapAnnotation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: current.latitude, longitude: current.longitude),
                    title: String(localized: "Current location"),
                    tint: .systemBlue)
                map.addAnnotation(annotation)
                points.append(current)
            }

            guard let first = points.first else { return }
            var rect = MKMapRect(
                x: MKMapPoint(
                    CLLocationCoordinate2D(
                        latitude: first.latitude, longitude: first.longitude)
                ).x,
                y: MKMapPoint(
                    CLLocationCoordinate2D(
                        latitude: first.latitude, longitude: first.longitude)
                ).y, width: 0, height: 0)
            for point in points.dropFirst() {
                let mapPoint = MKMapPoint(
                    CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
            }
            if rect.width < 1 || rect.height < 1 {
                rect = rect.insetBy(dx: -250, dy: -250)
            } else {
                rect = rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.25)
            }
            map.setVisibleMapRect(rect, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 4
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? SurveyMapAnnotation else { return nil }
            let identifier = "survey-point"
            let view =
                mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = annotation.tint
            view.glyphImage = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: nil)
            view.canShowCallout = true
            return view
        }

        private static func color(for rssi: Int) -> NSColor {
            if rssi >= -55 { return .systemGreen }
            if rssi >= -70 { return .systemMint }
            if rssi >= -80 { return .systemOrange }
            return .systemRed
        }
    }
}

/// Debug snapshot surface: the real map bridge with a deterministic demo walk.
struct SurveyMapPreview: View {
    var body: some View {
        SurveyTrackMap(track: GPXCodec.demoTrack(), samples: [], current: nil)
            .frame(width: 900, height: 520)
    }
}

private final class SurveyMapAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let tint: NSColor

    init(coordinate: CLLocationCoordinate2D, title: String, tint: NSColor) {
        self.coordinate = coordinate
        self.title = title
        self.tint = tint
    }
}
