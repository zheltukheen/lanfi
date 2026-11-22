import AppKit
import Foundation
import SwiftUI

@MainActor
final class SurveyViewModel: ObservableObject {
    @Published private(set) var project: SurveyProject
    @Published private(set) var projects: [SurveyProject] = []
    @Published private(set) var floorPlanData: Data?
    @Published var selectedNetworkId: String?
    @Published var statusMessage: String = String(localized: "Import a floor plan, then click to record signal.")

    private let store = SurveyStore()
    private var pendingSave: DispatchWorkItem?

    init() {
        if let latest = store.latestProject() {
            project = latest
            floorPlanData = store.imageData(for: latest)
            statusMessage = String(
                format: String(localized: "Loaded %@ · %lld points"), latest.name, latest.samples.count)
        } else {
            project = .new()
        }
        projects = store.projects()
        if !projects.contains(where: { $0.id == project.id }) {
            projects.insert(project, at: 0)
        }
    }

    var floorPlanImage: NSImage? {
        floorPlanData.flatMap(NSImage.init(data:))
    }

    /// A survey is placeable when it has an imported image or a hand-drawn plan.
    var hasPlan: Bool { floorPlanImage != nil || project.planWidthMeters != nil }

    @Published private(set) var isMeasuringPoint = false

    var samples: [SurveySample] { project.samples }
    var walls: [SurveyWall] { project.walls }
    var obstacles: [SurveyObstacle] { project.obstacles }
    var accessPoints: [SurveyAccessPoint] { project.accessPoints }
    var gpsTrack: [GeoPoint] { project.gpsTrack ?? [] }

    func samples(for network: NetworkModel?) -> [SurveySample] {
        guard let network else { return project.samples }
        return project.samples.filter { $0.bssid == network.bssid && $0.ssid == network.ssid }
    }

    func importFloorPlan() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a floor plan")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let image = NSImage(contentsOf: url),
            let data = pngData(for: image)
        else { return }

        let name = "floorplan-\(project.id.uuidString).png"
        project.imageFileName = name
        project.updatedAt = Date()
        floorPlanData = data
        store.save(project, imageData: data)
        statusMessage = String(localized: "Floor plan loaded. Click on the plan to record signal.")
    }

    func addSample(x: Double, y: Double, network: NetworkModel, coordinate: GeoPoint? = nil) {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let sample = SurveySample(
            id: UUID(),
            x: clampedX,
            y: clampedY,
            rssi: network.signal,
            ssid: network.displaySSID,
            bssid: network.bssid,
            recordedAt: Date(),
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude
        )
        project.samples.append(sample)
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = String(
            format: String(localized: "Recorded %lld dBm for %@."), network.signal, network.displaySSID)
    }

    /// Runs networkQuality once and stores its result on the newest point, so a
    /// walk can pair RSSI with the throughput actually available there.
    func measureLastSample() {
        guard !isMeasuringPoint, let sample = project.samples.last else { return }
        isMeasuringPoint = true
        Task {
            defer { isMeasuringPoint = false }
            do {
                let report = try await ThroughputTester.run(timeout: 10)
                guard let index = project.samples.firstIndex(where: { $0.id == sample.id }) else {
                    return
                }
                project.samples[index].downloadMbps = report.downloadMbps
                project.samples[index].latencyMilliseconds = report.latencyMilliseconds
                project.samples[index].measuredAt = report.testedAt
                project.updatedAt = Date()
                save()
                statusMessage = String(
                    format: String(localized: "Point measured · %@ · %@"),
                    report.downloadMbps.map { String(format: "%.0f Mbps", $0) }
                        ?? String(localized: "down —"),
                    report.latencyMilliseconds.map { String(format: "%.0f ms", $0) }
                        ?? String(localized: "latency —"))
            } catch {
                statusMessage = String(
                    format: String(localized: "Point measurement failed: %@"),
                    error.localizedDescription)
            }
        }
    }

    func removeSample(id: UUID) {
        let before = project.samples.count
        project.samples.removeAll { $0.id == id }
        guard project.samples.count != before else { return }
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = String(format: String(localized: "Point removed · %lld left."), project.samples.count)
    }

    func removeLastSample() {
        guard let sample = project.samples.last else { return }
        removeSample(id: sample.id)
    }

    func renameProject(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.name = trimmed
        project.updatedAt = Date()
        save()
        statusMessage = String(format: String(localized: "Renamed to %@."), trimmed)
    }

    func addWall(
        x1: Double, y1: Double, x2: Double, y2: Double,
        material: SurveyWallMaterial? = nil
    ) {
        project.walls.append(
            .new(
                x1: min(max(x1, 0), 1), y1: min(max(y1, 0), 1),
                x2: min(max(x2, 0), 1), y2: min(max(y2, 0), 1),
                material: material
            )
        )
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = String(
            format: String(localized: "Wall added · %lld dB attenuation."),
            Int(project.walls.last?.attenuationDb ?? 8))
    }

    func addObstacle(points: [SurveyPoint]) {
        guard points.count >= 3 else { return }
        let clamped = points.map {
            SurveyPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1))
        }
        project.obstacles.append(.new(points: clamped))
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = String(format: String(localized: "Room added · %lld rooms."), project.obstacles.count)
    }

    func addAccessPoint(x: Double, y: Double, band: String, channel: Int) {
        project.accessPoints.append(
            .new(x: min(max(x, 0), 1), y: min(max(y, 0), 1), band: band, channel: channel)
        )
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = String(format: String(localized: "Predictive AP added · %lld APs."), project.accessPoints.count)
    }

    /// Survey Planning 2.0 writes the suggested layout into the project.
    func applyPlannedAccessPoints(_ points: [SurveyPoint], band: String, channel: Int) {
        project.accessPoints = points.map {
            .new(
                x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1), band: band, channel: channel)
        }
        project.updatedAt = Date()
        save()
        statusMessage = String(
            format: String(localized: "Planned %lld access points."), project.accessPoints.count)
    }

    /// Imports a GPX walk; the map view draws it and can tag samples.
    func setGPSTrack(_ points: [GeoPoint]) {
        project.gpsTrack = points.isEmpty ? nil : points
        project.updatedAt = Date()
        save()
        statusMessage = String(
            format: String(localized: "GPS track · %lld points · %.0f m."), points.count,
            GeoMath.spanMeters(points))
    }

    /// Attaches a current position to the newest sample, which is how a
    /// walk-through gets map coordinates without re-recording.
    func tagLastSample(latitude: Double, longitude: Double) {
        guard var sample = project.samples.last else { return }
        sample.latitude = latitude
        sample.longitude = longitude
        project.samples[project.samples.count - 1] = sample
        if project.gpsTrack?.isEmpty ?? true {
            project.gpsTrack = [GeoPoint(latitude: latitude, longitude: longitude)]
        } else {
            project.gpsTrack?.append(GeoPoint(latitude: latitude, longitude: longitude))
        }
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = String(localized: "Last sample tagged with the current location.")
    }

    func clearAccessPoints() {
        project.accessPoints.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = String(localized: "Predictive APs cleared.")
    }

    func clearObstacles() {
        project.obstacles.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = String(localized: "Rooms cleared.")
    }

    func calibrateScale(realMeters: Double, normalizedDistance: Double) {
        guard realMeters > 0, normalizedDistance > 0 else { return }
        project.planWidthMeters = realMeters / normalizedDistance
        project.updatedAt = Date()
        save()
        statusMessage = String(
            format: String(localized: "Calibrated: plan width %.1f m."), project.planWidthMeters ?? 0)
    }

    func updateReportMetadata(title: String, client: String, planWidth: String, notes: String) {
        project.reportTitle = title.isEmpty ? nil : title
        project.clientName = client.isEmpty ? nil : client
        project.planWidthMeters = Double(planWidth.replacingOccurrences(of: ",", with: "."))
        project.reportNotes = notes.isEmpty ? nil : notes
        project.updatedAt = Date()
        save()
    }

    func floorImage(for project: SurveyProject) -> NSImage? {
        store.imageData(for: project).flatMap(NSImage.init(data:))
    }

    func exportAllFloorsPDF(networkName: String) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export all floors")
        panel.nameFieldStringValue = "LanFi-Survey-All-Floors.pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let all = projects.isEmpty ? [project] : projects
        let images = Dictionary(
            uniqueKeysWithValues: all.map { ($0.id, store.imageData(for: $0).flatMap(NSImage.init(data:))) })
        let data = SurveyReportExporter.makePortfolioPDF(
            projects: all, images: images, networkName: networkName
        )
        try? data.write(to: url, options: .atomic)
    }

    func clearWalls() {
        project.walls.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = String(localized: "Walls cleared.")
    }

    func selectProject(id: UUID) {
        guard id != project.id else { return }
        // Preserve the current floor before switching away from it.
        save()
        guard let selected = projects.first(where: { $0.id == id }) else { return }
        project = selected
        floorPlanData = store.imageData(for: selected)
        statusMessage = String(
            format: String(localized: "Loaded %@ · %lld points"), selected.name, selected.samples.count)
    }

    /// Creates an image-less plan: a metre grid the user can draw walls, rooms
    /// and sample points on without importing anything.
    func createBlankPlan(name: String, widthMeters: Double, heightMeters: Double) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { project.name = trimmed }
        project.planWidthMeters = min(max(widthMeters, 3), 200)
        project.planHeightMeters = min(max(heightMeters, 3), 200)
        project.imageFileName = nil
        project.updatedAt = Date()
        floorPlanData = nil
        save()
        projects = store.projects()
        statusMessage = String(
            format: String(localized: "Blank plan created · %.0f × %.0f m. Draw walls and click to sample."),
            project.planWidthMeters ?? 0, project.planHeightMeters ?? 0)
    }

    func newFloor() {
        let alert = NSAlert()
        alert.messageText = String(localized: "New floor")
        alert.informativeText = String(localized: "Create a separate floor plan and survey.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = String(localized: "Floor name")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var newProject = SurveyProject.new(
            name: name.isEmpty ? String(localized: "New floor") : name)
        newProject.floorLevel = (projects.map(\.floorLevel).max() ?? -1) + 1
        store.save(newProject, imageData: nil)
        projects = store.projects()
        project = newProject
        floorPlanData = nil
        statusMessage = String(
            format: String(localized: "Created %@. Import a floor plan to begin."), newProject.name)
    }

    func exportPDF(networkName: String, samples: [SurveySample]? = nil) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export survey report")
        panel.nameFieldStringValue = "LanFi-Survey-\(project.name).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = SurveyReportExporter.makePDF(
            project: project, image: floorPlanImage, networkName: networkName,
            samples: samples
        )
        try? data.write(to: url, options: .atomic)
    }

    #if DEBUG
        /// Snapshot harness only: an in-memory floor with samples, walls and
        /// predicted APs. Never saved, so the reviewer's survey files stay put.
        func loadDemoProject() {
            pendingSave?.cancel()
            let demo = DemoData.surveyProject()
            project = demo
            projects = [demo]
            floorPlanData = nil
            selectedNetworkId = nil
            statusMessage = String(
                format: String(localized: "Loaded %@ · %lld points"), demo.name,
                demo.samples.count)
        }
    #endif

    func clearSamples() {
        project.samples.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = String(localized: "Survey points cleared.")
    }

    func save() {
        store.save(project, imageData: floorPlanData)
        projects = store.projects()
        if !projects.contains(where: { $0.id == project.id }) {
            projects.insert(project, at: 0)
        }
        statusMessage = String(localized: "Survey saved locally.")
    }

    func selectLatest() {
        guard let latest = store.latestProject() else { return }
        project = latest
        floorPlanData = store.imageData(for: latest)
        statusMessage = String(format: String(localized: "Loaded %@."), latest.name)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
