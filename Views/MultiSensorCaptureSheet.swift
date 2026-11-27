import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// G3: one capture across the saved sensors, merged into a single pcapng.
struct MultiSensorCaptureSheet: View {
    let sensors: [RemoteSensor]
    @Environment(\.dismiss) private var dismiss
    @State private var interfaceName = "en0"
    @State private var duration = 20
    @State private var monitorMode = true
    @State private var filter = ""
    @State private var isCapturing = false
    @State private var progressText: String?
    @State private var result: MultiSensorCaptureResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
            AppSheetHeader(
                icon: "square.stack.3d.up",
                title: "Capture on all sensors",
                subtitle:
                    "Runs one tcpdump per sensor and merges the captures into a single pcapng with one interface per sensor, so Wireshark shows which radio saw each frame."
            ) {
                Button("Close") { dismiss() }
            }

            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    SectionLabel(text: "Capture")
                    HStack(spacing: DesignToken.Spacing.small) {
                        TextField("Interface", text: $interfaceName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        Picker("Duration", selection: $duration) {
                            Text("10 seconds").tag(10)
                            Text("20 seconds").tag(20)
                            Text("30 seconds").tag(30)
                            Text("60 seconds").tag(60)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        Toggle("Monitor mode / radiotap", isOn: $monitorMode)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Spacer()
                    }
                    TextField("BPF filter", text: $filter)
                        .textFieldStyle(.roundedBorder)
                    Text(
                        "Captures run one sensor at a time; a failed sensor is skipped and reported instead of discarding the rest."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "Sensors")
                ForEach(sensors) { sensor in
                    HStack(spacing: DesignToken.Spacing.small) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .frame(width: 18)
                        Text(sensor.name)
                            .font(.caption)
                        Text("\(sensor.username)@\(sensor.host)")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }

            if let errorMessage {
                ToolkitErrorBanner(message: errorMessage)
            }
            if let result {
                resultCard(result)
            }
            if let progressText {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()
                AppButton(
                    "Start capture", tone: .primary, isBusy: isCapturing,
                    isEnabled: !isCapturing && !sensors.isEmpty
                ) {
                    start()
                }
            }
        }
        .appSheet(width: DesignToken.Layout.sheetWidthWide, minHeight: 460)
    }

    private func resultCard(_ result: MultiSensorCaptureResult) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            if let url = result.mergedURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(
                        String(
                            format: String(localized: "Merged %lld frames from %lld sensors."),
                            result.packetCount, result.sensorNames.count)
                    )
                    .font(.caption)
                    Spacer()
                    AppButton("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Text(url.path)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("No sensor produced a capture. See the failures below.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !result.failures.isEmpty {
                SectionLabel(text: "Sensors that failed")
                ForEach(result.failures, id: \.sensor) { failure in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(failure.sensor).font(.caption.bold())
                            Text(failure.message)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func start() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-MultiSensor.pcapng"
        panel.allowedContentTypes = [.data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isCapturing = true
        errorMessage = nil
        result = nil
        progressText = nil
        let settings = MultiSensorCaptureService.Settings(
            interfaceName: interfaceName, duration: duration, monitorMode: monitorMode,
            filter: filter)
        Task {
            do {
                let outcome = try await MultiSensorCaptureService.capture(
                    sensors: sensors, settings: settings, mergedURL: url
                ) { index, name in
                    progressText = String(
                        format: String(localized: "Capturing %lld of %lld · %@"),
                        index + 1, sensors.count, name)
                }
                result = outcome
            } catch {
                errorMessage = error.localizedDescription
            }
            progressText = nil
            isCapturing = false
        }
    }
}
