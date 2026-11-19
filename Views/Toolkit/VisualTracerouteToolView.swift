import AppKit
import MapKit
import SwiftUI

struct VisualTracerouteToolView: View {
    @ObservedObject var model: VisualTracerouteToolModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            if let error = model.errorMessage {
                ToolkitErrorBanner(message: error)
            }
            HStack(alignment: .top, spacing: 12) {
                map
                hopList
            }
            .frame(minHeight: 240, maxHeight: .infinity)
            if !model.hops.isEmpty {
                hopTable
            }
        }
        .appContentPadding()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.hops.count)
    }

    // MARK: - Controls

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: 10) {
                    ToolTargetField(
                        text: $model.host, placeholder: "Host or IP address",
                        onSubmit: { model.run() })
                    Stepper("Max hops: \(model.maxHops)", value: $model.maxHops, in: 1...40)
                        .font(.caption)
                    if model.isRunning {
                        Button("Stop") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Trace") { model.run() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Copy") { copyRoute() }
                        .buttonStyle(.bordered)
                        .disabled(model.hops.isEmpty)
                        .help("Copy the hop list as text")
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.hops.isEmpty)
                    Spacer()
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                // The classic Traceroute screen's controls live here now, so the
                // merged view can probe as often and as long as it used to.
                HStack(spacing: 16) {
                    Stepper("Probes: \(model.probes)", value: $model.probes, in: 1...3)
                        .font(.caption)
                        .fixedSize()
                    Stepper("Timeout: \(model.waitSeconds) s", value: $model.waitSeconds, in: 1...10)
                        .font(.caption)
                        .fixedSize()
                    Toggle("Resolve names", isOn: $model.resolveNames)
                        .font(.caption)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Hop table

    /// The sortable hop table from the classic Traceroute screen: the map shows
    /// where the route goes, this shows exactly what each probe returned.
    private var hopTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Hops")
                    Spacer()
                    Text(model.host)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                AppTable(
                    columns: hopColumns, rows: model.hops, initialKey: "ttl"
                )
                .frame(height: ToolkitTableHeight.rows(model.hops.count, minimum: 120, maximum: 260))
            }
        }
    }

    private var hopColumns: [AppTableColumn<VisualTracerouteHop>] {
        [
            AppTableColumn(
                id: "ttl", title: "Hop", minWidth: 40,
                value: { .number($0.id) },
                cell: { hop in
                    AnyView(
                        Text("\(hop.id)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary))
                }),
            AppTableColumn(
                id: "address", title: "Address", minWidth: 130,
                value: { .text($0.hop.address) },
                cell: { hop in
                    AnyView(
                        Text(hop.hop.address ?? "*")
                            .font(.caption.monospaced())
                            .lineLimit(1))
                }),
            AppTableColumn(
                id: "name", title: "Name", minWidth: 120,
                value: { .text($0.hop.hostname) },
                cell: { hop in
                    AnyView(
                        Text(hop.hop.hostname ?? "—")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1))
                }),
            AppTableColumn(
                id: "latency", title: "Latency", minWidth: 70,
                value: { .number($0.hop.averageMilliseconds) },
                cell: { hop in
                    AnyView(
                        Text(
                            hop.hop.averageMilliseconds.map { String(format: "%.1f ms", $0) } ?? "—"
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary))
                }),
            AppTableColumn(
                id: "location", title: "Location", minWidth: 160,
                value: { .text([$0.geo?.city, $0.geo?.country].compactMap { $0 }.joined(separator: ", ")) },
                cell: { hop in
                    AnyView(
                        Text(
                            [hop.geo?.city, hop.geo?.country]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: ", ")
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1))
                }),
        ]
    }

    private var statusText: String {
        switch model.phase {
        case .idle:
            return model.hops.isEmpty
                ? String(localized: "Ready")
                : String(format: String(localized: "%lld hops"), model.hops.count)
        case .tracing:
            return String(localized: "Tracing…")
        case .retrying:
            return String(localized: "Retrying…")
        }
    }

    private var statusTone: ToolkitTone {
        switch model.phase {
        case .idle: return model.hops.isEmpty ? .neutral : .good
        case .tracing, .retrying: return .running
        }
    }

    // MARK: - Map

    private var map: some View {
        ZStack(alignment: .topLeading) {
            RouteMapView(nodes: mapNodes, links: mapLinks, focusToken: model.startedAt)
            VStack(alignment: .leading, spacing: 8) {
                progressCard
                Spacer(minLength: 0)
                legend
            }
            .padding(DesignToken.Spacing.medium)
            if model.hops.isEmpty && !model.isRunning {
                emptyHint
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Radius.card)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(headline)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(model.probe.rawValue.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            Text(detail)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
        }
        .padding(DesignToken.Spacing.compact)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignToken.Radius.card))
    }

    private var headline: String {
        switch model.phase {
        case .idle:
            if model.hops.isEmpty { return String(localized: "Ready to trace") }
            return String(
                format: String(localized: "Trace finished · %lld hops"), model.hops.count)
        case .tracing:
            return String(format: String(localized: "Tracing %@"), model.host)
        case .retrying:
            return String(localized: "Retrying with UDP probes")
        }
    }

    private var detail: String {
        if model.isRunning {
            if let address = model.currentAddress {
                let latency = model.currentMilliseconds.map { String(format: " · %.1f ms", $0) } ?? ""
                return "\(address)\(latency)"
            }
            return String(localized: "Waiting for replies…")
        }
        guard !model.hops.isEmpty else {
            return String(localized: "Public hops are pinned as they respond")
        }
        return String(
            format: String(localized: "%lld of %lld hops mapped"), model.mappedCount,
            model.hops.count)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: .systemGreen, text: "< 40 ms")
            legendItem(color: .systemYellow, text: "< 120 ms")
            legendItem(color: .systemOrange, text: "≥ 120 ms")
        }
        .padding(.horizontal, DesignToken.Spacing.compact)
        .padding(.vertical, DesignToken.Spacing.tight)
        .background(.regularMaterial, in: Capsule())
    }

    private func legendItem(color: NSColor, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Trace a route on the map")
                .font(.callout.weight(.medium))
            Text("The map follows the trace hop by hop.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .appContentPadding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignToken.Radius.sheet))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapNodes: [RouteMapNode] {
        var nodes: [RouteMapNode] = []
        if let origin = model.origin {
            nodes.append(
                RouteMapNode(
                    id: "origin",
                    coordinate: CLLocationCoordinate2D(
                        latitude: origin.latitude, longitude: origin.longitude),
                    title: String(localized: "This Mac"),
                    subtitle: origin.locationLine,
                    kind: .origin,
                    band: .unknown,
                    isCurrent: false
                ))
        }
        for hop in model.hops {
            guard let geo = hop.geo else { continue }
            nodes.append(
                RouteMapNode(
                    id: "hop-\(hop.id)",
                    coordinate: CLLocationCoordinate2D(
                        latitude: geo.latitude, longitude: geo.longitude),
                    title: "\(hop.id). \(hopTitle(hop))",
                    subtitle: [geo.flagEmoji, geo.isp].filter { !$0.isEmpty }.joined(
                        separator: " "),
                    kind: .hop,
                    band: VisualRouteLatency.band(for: hop.hop.averageMilliseconds),
                    isCurrent: hop.id == model.currentTTL
                ))
        }
        if let destination = model.destination,
            !model.hops.contains(where: { $0.geo?.ip == destination.ip })
        {
            nodes.append(
                RouteMapNode(
                    id: "destination",
                    coordinate: CLLocationCoordinate2D(
                        latitude: destination.latitude, longitude: destination.longitude),
                    title: model.host,
                    subtitle: destination.locationLine,
                    kind: .destination,
                    band: .unknown,
                    isCurrent: false
                ))
        }
        return nodes
    }

    private var mapLinks: [VisualRouteLink] {
        VisualTraceroutePath.links(origin: model.origin, hops: model.hops)
    }

    private func hopTitle(_ hop: VisualTracerouteHop) -> String {
        guard let geo = hop.geo else { return hop.hop.address ?? "*" }
        return [geo.city, geo.country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: - Hop list

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
                        .lineLimit(1)
                }
                .padding(.bottom, DesignToken.Spacing.tight)

                ForEach(model.hops) { hop in
                    hopRow(hop)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if model.isRunning {
                    waitingRow
                }

                Text("GeoIP lookups use ipwho.is; only public hop addresses are sent.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, DesignToken.Spacing.small)
            }
            .padding(DesignToken.Spacing.compact)
        }
        .frame(width: 350)
        .background(
            Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DesignToken.Radius.card))
    }

    private var waitingRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20)
            Text(
                model.phase == .retrying
                    ? String(localized: "Retrying with UDP probes…")
                    : String(localized: "Waiting for hop \(model.hops.count + 1)…")
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, DesignToken.Spacing.tight)
    }

    private func hopRow(_ hop: VisualTracerouteHop) -> some View {
        let isCurrent = hop.id == model.currentTTL
        return HStack(alignment: .top, spacing: 8) {
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
        .padding(.vertical, DesignToken.Spacing.tight)
        .padding(.horizontal, DesignToken.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                .fill(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .accessibilityElement(children: .combine)
    }

    private func copyRoute() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.copyText, forType: .string)
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

// MARK: - Map nodes

private enum RouteMapKind {
    case origin
    case hop
    case destination
}

private struct RouteMapNode: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let kind: RouteMapKind
    let band: VisualRouteLatency
    let isCurrent: Bool

    var tint: NSColor {
        if isCurrent { return .controlAccentColor }
        switch kind {
        case .origin: return .systemGreen
        case .destination: return .systemPink
        case .hop:
            switch band {
            case .fast: return .systemGreen
            case .moderate: return .systemYellow
            case .slow: return .systemOrange
            case .unknown: return .systemGray
            }
        }
    }

    var glyphText: String? {
        if kind == .hop { return String(id.dropFirst(5)) }
        return nil
    }

    var glyphSymbol: String? {
        switch kind {
        case .origin: return "desktopcomputer"
        case .destination: return "flag.checkered"
        case .hop: return nil
        }
    }
}

private final class RouteAnnotation: NSObject, MKAnnotation {
    var node: RouteMapNode
    dynamic var coordinate: CLLocationCoordinate2D

    init(node: RouteMapNode) {
        self.node = node
        self.coordinate = node.coordinate
        super.init()
    }

    var title: String? { node.title }
    var subtitle: String? { node.subtitle }
}

private final class RouteAnnotationView: MKMarkerAnnotationView {
    static let reuseIdentifier = "RouteHop"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        animatesWhenAdded = true
        displayPriority = .required
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ node: RouteMapNode) {
        markerTintColor = node.tint
        if let symbol = node.glyphSymbol {
            glyphImage = NSImage(systemSymbolName: symbol, accessibilityDescription: node.title)
            glyphText = nil
        } else {
            glyphImage = nil
            glyphText = node.glyphText
        }
        displayPriority = node.isCurrent ? .required : .defaultHigh
        zPriority = node.isCurrent ? .max : .defaultSelected
    }
}

private struct RouteMapView: NSViewRepresentable {
    let nodes: [RouteMapNode]
    let links: [VisualRouteLink]
    let focusToken: Date?

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
        let coordinator = context.coordinator
        updateAnnotations(on: map)
        updateOverlays(on: map, coordinator: coordinator)
        frame(map, coordinator: coordinator)
    }

    private func updateAnnotations(on map: MKMapView) {
        let existing = map.annotations.compactMap { $0 as? RouteAnnotation }
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.node.id, $0) })

        for node in nodes {
            if let annotation = byID.removeValue(forKey: node.id) {
                annotation.node = node
                if annotation.coordinate.latitude != node.coordinate.latitude
                    || annotation.coordinate.longitude != node.coordinate.longitude
                {
                    annotation.coordinate = node.coordinate
                }
                if let view = map.view(for: annotation) as? RouteAnnotationView {
                    view.apply(node)
                }
            } else {
                map.addAnnotation(RouteAnnotation(node: node))
            }
        }
        if !byID.isEmpty {
            map.removeAnnotations(Array(byID.values))
        }
    }

    private func updateOverlays(on map: MKMapView, coordinator: Coordinator) {
        map.removeOverlays(map.overlays)
        coordinator.lineColors.removeAll()
        for link in links {
            var coordinates = [
                CLLocationCoordinate2D(
                    latitude: link.fromLatitude, longitude: link.fromLongitude),
                CLLocationCoordinate2D(latitude: link.toLatitude, longitude: link.toLongitude),
            ]
            let line = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            coordinator.lineColors[ObjectIdentifier(line)] = Coordinator.color(
                for: VisualRouteLatency.band(for: link.milliseconds))
            map.addOverlay(line)
        }
    }

    private func frame(_ map: MKMapView, coordinator: Coordinator) {
        guard let first = nodes.first else { return }
        var rect = MKMapRect.null
        for node in nodes {
            let point = MKMapPoint(node.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let tokenChanged = coordinator.focusToken != focusToken
        coordinator.focusToken = focusToken

        let span = rect.size
        if span.width < 1 || span.height < 1 {
            if tokenChanged || map.region.span.latitudeDelta > 12 {
                map.setRegion(
                    MKCoordinateRegion(
                        center: first.coordinate,
                        latitudinalMeters: 900_000,
                        longitudinalMeters: 900_000),
                    animated: true
                )
            }
            return
        }
        if tokenChanged || !map.visibleMapRect.contains(rect) {
            map.setVisibleMapRect(
                rect,
                edgePadding: NSEdgeInsets(top: 70, left: 90, bottom: 70, right: 90),
                animated: true
            )
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lineColors: [ObjectIdentifier: NSColor] = [:]
        var focusToken: Date?

        static func color(for band: VisualRouteLatency) -> NSColor {
            switch band {
            case .fast: return .systemGreen
            case .moderate: return .systemYellow
            case .slow: return .systemOrange
            case .unknown: return .controlAccentColor
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let route = annotation as? RouteAnnotation else { return nil }
            let view =
                (mapView.dequeueReusableAnnotationView(
                    withIdentifier: RouteAnnotationView.reuseIdentifier)
                    as? RouteAnnotationView)
                ?? RouteAnnotationView(
                    annotation: annotation, reuseIdentifier: RouteAnnotationView.reuseIdentifier)
            view.annotation = annotation
            view.apply(route.node)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = lineColors[ObjectIdentifier(line)] ?? .controlAccentColor
            renderer.lineWidth = 4
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}
