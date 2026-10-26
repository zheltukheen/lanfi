import SwiftUI

struct LiveCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var interfaces: [String] = []
    @State private var selectedInterface = "en0"
    @State private var duration = 20
    @State private var startDelay = 0
    @State private var monitorMode = true
    @State private var outputURL = LiveCaptureView.defaultOutputURL()
    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var completedURL: URL?
    @State private var showingAnalysis = false
    @State private var customOutput = false
    @State private var filter = ""
    @State private var profiles: [CaptureProfile] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live packet capture")
                        .font(.title3.bold())
                    Text("Writes a standard pcap using macOS tcpdump and BPF.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Menu("Profiles") {
                    ForEach(profiles) { profile in
                        Button(profile.name) { apply(profile) }
                    }
                    if !profiles.isEmpty { Divider() }
                    Button("Save current…") { saveProfile() }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 90)
                Button("Close") { dismiss() }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Interface").foregroundColor(.secondary)
                    Picker("", selection: $selectedInterface) {
                        ForEach(interfaces, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                GridRow {
                    Text("Duration").foregroundColor(.secondary)
                    Picker("", selection: $duration) {
                        Text("10 seconds").tag(10)
                        Text("20 seconds").tag(20)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                GridRow {
                    Text("Start delay").foregroundColor(.secondary)
                    Picker("", selection: $startDelay) {
                        Text("No delay").tag(0)
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                GridRow {
                    Text("BPF filter").foregroundColor(.secondary)
                    TextField("e.g. type mgt subtype beacon", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                GridRow {
                    Text("Output").foregroundColor(.secondary)
                    HStack {
                        Text(outputURL.path)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 360, alignment: .leading)
                        Button("Choose…") { chooseOutput() }
                            .controlSize(.small)
                    }
                }
            }

            Toggle("Monitor mode / radiotap (Wi-Fi interfaces)", isOn: $monitorMode)
                .disabled(!selectedInterface.hasPrefix("en"))
                .help("Adds -I -y IEEE802_11_RADIO. Disable if the driver rejects monitor mode.")

            Text(
                "macOS requires administrator authorization for BPF. LanFi does not install a privileged helper or store credentials. Built-in Apple Wi-Fi adapters often expose monitor mode but deliver zero frames; use an external monitor-capable adapter, or use Data → Export PCAP (Synthetic Beacons) for offline analysis."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
            if completedURL != nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Saved \(savedURL.lastPathComponent)")
                        .font(.caption)
                    Button("Analyze capture") {
                        showingAnalysis = true
                    }
                    .controlSize(.small)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                    }
                    .controlSize(.small)
                    Button("New capture") {
                        outputURL = Self.defaultOutputURL()
                        completedURL = nil
                        customOutput = false
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            HStack {
                Spacer()
                if isCapturing {
                    ProgressView().controlSize(.small)
                    Text("Capturing… authorize the macOS prompt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button("Start Capture") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturing || interfaces.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 590)
        .sheet(isPresented: $showingAnalysis) {
            OfflineCaptureView(initialURL: completedURL)
        }
        .onAppear {
            interfaces = LiveCaptureService.interfaceNames()
            if !interfaces.contains(selectedInterface), let first = interfaces.first {
                selectedInterface = first
            }
            monitorMode = selectedInterface == "en0"
            profiles = CaptureProfileStore().load()
        }
    }

    private var savedURL: URL {
        completedURL ?? URL(fileURLWithPath: "")
    }

    private func start() {
        errorMessage = nil
        completedURL = nil
        if !customOutput { outputURL = Self.defaultOutputURL() }
        let options = LiveCaptureOptions(
            interfaceName: selectedInterface,
            duration: duration,
            outputURL: outputURL,
            monitorMode: monitorMode && selectedInterface.hasPrefix("en"),
            filter: filter,
            startDelay: startDelay
        )
        isCapturing = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await LiveCaptureService.capture(options)
                }.value
                await MainActor.run {
                    isCapturing = false
                    completedURL = result
                }
            } catch {
                await MainActor.run {
                    isCapturing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func apply(_ profile: CaptureProfile) {
        selectedInterface = profile.interfaceName
        duration = profile.duration
        monitorMode = profile.monitorMode
        filter = profile.filter
    }

    private func saveProfile() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.stringValue = "Capture profile"
        let alert = NSAlert()
        alert.messageText = "Save capture profile"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profile = CaptureProfile.new(
            name: name, interfaceName: selectedInterface, duration: duration,
            monitorMode: monitorMode, filter: filter
        )
        if let index = profiles.firstIndex(where: { $0.name == name }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        CaptureProfileStore().save(profiles)
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.title = "Save packet capture"
        panel.nameFieldStringValue = outputURL.lastPathComponent
        panel.allowedContentTypes = [.init(filenameExtension: "pcap") ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
            customOutput = true
        }
    }

    private static func defaultOutputURL() -> URL {
        let folder =
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let suffix = UUID().uuidString.prefix(6)
        return folder.appendingPathComponent("LanFi-\(stamp)-\(suffix).pcap")
    }
}
