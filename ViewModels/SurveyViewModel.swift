import AppKit
import Foundation
import SwiftUI

@MainActor
final class SurveyViewModel: ObservableObject {
    @Published private(set) var project: SurveyProject
    @Published private(set) var projects: [SurveyProject] = []
    @Published private(set) var floorPlanData: Data?
    @Published var selectedNetworkId: String?
    @Published var statusMessage: String = "Import a floor plan, then click to record signal."

    private let store = SurveyStore()
    private var pendingSave: DispatchWorkItem?

    init() {
        if let latest = store.latestProject() {
            project = latest
            floorPlanData = store.imageData(for: latest)
            statusMessage = "Loaded \(latest.name) · \(latest.samples.count) points"
        } else {
            project = .new()
        }
        projects = store.projects()
    }

    var floorPlanImage: NSImage? {
        floorPlanData.flatMap(NSImage.init(data:))
    }

    var samples: [SurveySample] { project.samples }
    var walls: [SurveyWall] { project.walls }
    var obstacles: [SurveyObstacle] { project.obstacles }
    var accessPoints: [SurveyAccessPoint] { project.accessPoints }

    func samples(for network: NetworkModel?) -> [SurveySample] {
        guard let network else { return project.samples }
        return project.samples.filter { $0.bssid == network.bssid && $0.ssid == network.ssid }
    }

    func importFloorPlan() {
        let panel = NSOpenPanel()
        panel.title = "Choose a floor plan"
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
        statusMessage = "Floor plan loaded. Click on the plan to record signal."
    }

    func addSample(x: Double, y: Double, network: NetworkModel) {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let sample = SurveySample(
            id: UUID(),
            x: clampedX,
            y: clampedY,
            rssi: network.signal,
            ssid: network.displaySSID,
            bssid: network.bssid,
            recordedAt: Date()
        )
        project.samples.append(sample)
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = "Recorded \(network.signal) dBm for \(network.displaySSID)."
    }

    func addWall(x1: Double, y1: Double, x2: Double, y2: Double) {
        project.walls.append(
            .new(
                x1: min(max(x1, 0), 1), y1: min(max(y1, 0), 1),
                x2: min(max(x2, 0), 1), y2: min(max(y2, 0), 1)
            )
        )
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = "Wall added · \(Int(project.walls.last?.attenuationDb ?? 8)) dB attenuation."
    }

    func addObstacle(points: [SurveyPoint]) {
        guard points.count >= 3 else { return }
        let clamped = points.map {
            SurveyPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1))
        }
        project.obstacles.append(.new(points: clamped))
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = "Room added · \(project.obstacles.count) rooms."
    }

    func addAccessPoint(x: Double, y: Double, band: String, channel: Int) {
        project.accessPoints.append(
            .new(x: min(max(x, 0), 1), y: min(max(y, 0), 1), band: band, channel: channel)
        )
        project.updatedAt = Date()
        scheduleSave()
        statusMessage = "Predictive AP added · \(project.accessPoints.count) APs."
    }

    func clearAccessPoints() {
        project.accessPoints.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = "Predictive APs cleared."
    }

    func clearObstacles() {
        project.obstacles.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = "Rooms cleared."
    }

    func updateReportMetadata(title: String, client: String, planWidth: String, notes: String) {
        project.reportTitle = title.isEmpty ? nil : title
        project.clientName = client.isEmpty ? nil : client
        project.planWidthMeters = Double(planWidth.replacingOccurrences(of: ",", with: "."))
        project.reportNotes = notes.isEmpty ? nil : notes
        project.updatedAt = Date()
        save()
    }

    func exportAllFloorsPDF(networkName: String) {
        let panel = NSSavePanel()
        panel.title = "Export all floors"
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
        statusMessage = "Walls cleared."
    }

    func selectProject(id: UUID) {
        guard let selected = projects.first(where: { $0.id == id }) else { return }
        project = selected
        floorPlanData = store.imageData(for: selected)
        statusMessage = "Loaded \(selected.name) · \(selected.samples.count) points"
    }

    func newFloor() {
        let alert = NSAlert()
        alert.messageText = "New floor"
        alert.informativeText = "Create a separate floor plan and survey."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = "Floor name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newProject = SurveyProject.new(name: name.isEmpty ? "New floor" : name)
        store.save(newProject, imageData: nil)
        projects = store.projects()
        project = newProject
        floorPlanData = nil
        statusMessage = "Created \(newProject.name). Import a floor plan to begin."
    }

    func exportPDF(networkName: String) {
        let panel = NSSavePanel()
        panel.title = "Export survey report"
        panel.nameFieldStringValue = "LanFi-Survey-\(project.name).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = SurveyReportExporter.makePDF(
            project: project, image: floorPlanImage, networkName: networkName
        )
        try? data.write(to: url, options: .atomic)
    }

    func clearSamples() {
        project.samples.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = "Survey points cleared."
    }

    func save() {
        store.save(project, imageData: floorPlanData)
        projects = store.projects()
        statusMessage = "Survey saved locally."
    }

    func selectLatest() {
        guard let latest = store.latestProject() else { return }
        project = latest
        floorPlanData = store.imageData(for: latest)
        statusMessage = "Loaded \(latest.name)."
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
