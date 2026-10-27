import AppKit
import SwiftUI

struct MultiFloorSurveyView: View {
    @ObservedObject var survey: SurveyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tilt = 48.0
    @State private var spacing = 110.0
    @State private var showPrediction = true

    private var floors: [SurveyProject] { survey.projects }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Multi-floor 3D view").font(.title3.bold())
                    Text("\(floors.count) floors · click a floor to open it").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(14)
            Divider()
            HStack(spacing: 18) {
                Label("Tilt", systemImage: "rotate.3d")
                Slider(value: $tilt, in: 0...75).frame(width: 180)
                Label("Spacing", systemImage: "square.3.layers.3d")
                Slider(value: $spacing, in: 40...180).frame(width: 160)
                Toggle("Coverage", isOn: $showPrediction)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .font(.caption)
            .padding(10)
            Divider()

            GeometryReader { geo in
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    if floors.isEmpty {
                        Text("Add floors in Site Survey first.").foregroundColor(.secondary)
                    } else {
                        ForEach(Array(floors.enumerated()), id: \.element.id) { index, floor in
                            floorCard(floor, index: index, total: floors.count, size: geo.size)
                        }
                    }
                }
            }
        }
        .frame(width: 860, height: 620)
    }

    private var floorInputs: [SurveyFloorInput] {
        floors.map {
            SurveyFloorInput(
                floorLevel: $0.floorLevel,
                floorHeightMeters: $0.floorHeightMeters,
                walls: $0.walls,
                obstacles: $0.obstacles,
                accessPoints: $0.accessPoints
            )
        }
    }

    private func predictionOverlay(for floor: SurveyProject) -> some View {
        Canvas { context, size in
            guard floorInputs.contains(where: { !$0.accessPoints.isEmpty }) else { return }
            let cell: CGFloat = 7
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let nx = Double(x / max(size.width, 1))
                    let ny = Double(y / max(size.height, 1))
                    if let rssi = SurveyPredictor.estimate3D(
                        x: nx, y: ny, targetFloorLevel: floor.floorLevel,
                        floors: floorInputs, planWidthMeters: floor.planWidthMeters ?? 30
                    ) {
                        let t = min(max(Double(rssi + 90) / 50.0, 0), 1)
                        let color = Color(red: 0.9 - t * 0.8, green: 0.2 + t * 0.7, blue: 0.15)
                        context.fill(
                            Path(CGRect(x: x, y: y, width: cell + 0.5, height: cell + 0.5)),
                            with: .color(color.opacity(0.45))
                        )
                    }
                    x += cell
                }
                y += cell
            }
        }
    }

    private func floorCard(_ floor: SurveyProject, index: Int, total: Int, size: CGSize) -> some View {
        let center = CGFloat(total - 1) / 2
        let offset = CGFloat(index) - center
        return VStack(spacing: 4) {
            if let image = survey.floorImage(for: floor) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 300, height: 180)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Text(floor.name)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .padding(6)
                    }
                    .overlay {
                        if showPrediction {
                            predictionOverlay(for: floor)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 300, height: 180)
                    .overlay(Text(floor.name).font(.headline))
            }
            HStack(spacing: 8) {
                Text("\(floor.samples.count) pts")
                Text("\(floor.obstacles.count) rooms")
                if !floor.accessPoints.isEmpty { Text("\(floor.accessPoints.count) APs") }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
        .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
        .offset(x: offset * 32, y: offset * -spacing)
        .zIndex(Double(-index))
        .onTapGesture {
            survey.selectProject(id: floor.id)
            dismiss()
        }
        .accessibilityLabel("Floor \(floor.name), \(floor.samples.count) samples")
    }
}
