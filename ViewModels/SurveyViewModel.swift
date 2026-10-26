import AppKit
import Foundation
import SwiftUI

@MainActor
final class SurveyViewModel: ObservableObject {
    @Published private(set) var project: SurveyProject
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
    }

    var floorPlanImage: NSImage? {
        floorPlanData.flatMap(NSImage.init(data:))
    }

    var samples: [SurveySample] { project.samples }

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

    func clearSamples() {
        project.samples.removeAll()
        project.updatedAt = Date()
        store.save(project, imageData: nil)
        statusMessage = "Survey points cleared."
    }

    func save() {
        store.save(project, imageData: floorPlanData)
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
