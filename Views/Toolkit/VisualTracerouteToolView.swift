import MapKit
import SwiftUI

struct VisualTracerouteToolView: View {
    @ObservedObject var model: VisualTracerouteToolModel

    private var mapPoints: [RouteMapPoint] {
        model.hops.compactMap { hop in
            guard let geo = hop.geo else { return nil }
            return RouteMapPoint(
                id: hop.id,
                coordinate: CLLocationCoordinate2D(
                    latitude: geo.latitude, longitude: geo.longitude),
                title: "\(hop.id). \(geo.city.isEmpty ? geo.ip : geo.city)",
                subtitle: geo.country
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            if let error = model.errorMessage {
                ToolkitErrorBanner(message: error)
            }
            if model.hops.isEmpty {
                if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "map",
                        title: "Trace a route on the map",
                        message:
                            "Runs traceroute, then resolves public hop addresses through ipwho.is. Private and timed-out hops stay in the list without a pin."
                    )
                } else {
                    ProgressView("Tracing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    map
                    hopList
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(18)
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                TextField("Host or IP address", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onSubmit { model.run() }
                Stepper("Max hops: \(model.maxHops)", value: $model.maxHops, in: 1...40)
                    .font(.caption)
                if model.isRunning {
                    Button("Stop") { model.stop() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Trace") { model.run() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .disabled(model.hops.isEmpty)
                Spacer()
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        switch model.phase {
        case .idle:
            return model.hops.isEmpty
                ? String(localized: "Ready")
                : String(format: String(localized: "%lld hops"), model.hops.count)
        case .tracing:
            return String(localized: "Tracing…")
        case .locating:
            return String(
                format: String(localized: "Locating %lld/%lld…"),
                model.mappedCount, model.hops.count)
        }
    }

    private var statusTone: ToolkitTone {
        switch model.phase {
        case .idle: return model.hops.isEmpty ? .neutral : .good
        case .tracing, .locating: return .running
        }
    }

    private var map: some View {
        ZStack {
            RouteMapView(points: mapPoints)
            if mapPoints.isEmpty {
                Text("No public hops to map")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var hopList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Route")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(model.host)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 6)
                ForEach(model.hops) { hop in
                    hopRow(hop)
                }
                Text("GeoIP lookups use ipwho.is; only public hop addresses are sent.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(10)
        }
        .frame(width: 350)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func hopRow(_ hop: VisualTracerouteHop) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(hop.id)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(hop.geo?.flag ?? "•")
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(locationTitle(hop))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(hop.hop.address ?? "*")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                if let hostname = hop.hop.hostname, !hostname.isEmpty {
                    Text(hostname)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let ms = hop.hop.averageMilliseconds {
                Text(String(format: "%.1f ms", ms))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func locationTitle(_ hop: VisualTracerouteHop) -> String {
        guard let geo = hop.geo else {
            if hop.hop.timedOut { return String(localized: "No response") }
            if let address = hop.hop.address,
                VisualTracerouteFilter.isPublic(address)
            {
                return String(localized: "Location unavailable")
            }
            return String(localized: "Private / local hop")
        }
        return [geo.city, geo.country].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct RouteMapPoint: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
}

private struct RouteMapView: NSViewRepresentable {
    let points: [RouteMapPoint]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.showsCompass = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)
        guard !points.isEmpty else { return }

        let annotations = points.map { point -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = point.coordinate
            annotation.title = point.title
            annotation.subtitle = point.subtitle
            return annotation
        }
        map.addAnnotations(annotations)

        if points.count > 1 {
            let coordinates = points.map(\.coordinate)
            map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
        }

        if points.count == 1, let point = points.first {
            map.setRegion(
                MKCoordinateRegion(
                    center: point.coordinate,
                    latitudinalMeters: 250_000,
                    longitudinalMeters: 250_000),
                animated: false
            )
            return
        }

        let latitudes = points.map(\.coordinate.latitude)
        let longitudes = points.map(\.coordinate.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 1),
            longitudeDelta: max((maxLon - minLon) * 1.5, 1)
        )
        map.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .controlAccentColor
            renderer.lineWidth = 3
            return renderer
        }
    }
}
