import SwiftUI

struct RemoteSensorsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sensors: [RemoteSensor]
    @State private var selectedID: UUID?
    @State private var results: [RemoteNetwork] = []
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var showingEditor = false
    @State private var editingSensor: RemoteSensor?
    @State private var autoRefresh = false

    private let store = RemoteSensorStore()

    init() {
        let loaded = RemoteSensorStore().sensors()
        _sensors = State(initialValue: loaded)
        _selectedID = State(initialValue: loaded.first?.id)
    }

    private var selected: RemoteSensor? {
        sensors.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remote sensors")
                        .font(.title3.bold())
                    Text("Run a scan on another Mac over SSH. Key-based login is required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(14)
            Divider()

            HSplitView {
                sidebar
                    .frame(minWidth: 220, idealWidth: 240)
                detail
                    .frame(minWidth: 480)
            }
        }
        .frame(width: 860, height: 540)
        .task(id: PollKey(id: selectedID, enabled: autoRefresh)) {
            guard autoRefresh, let selected else { return }
            while !Task.isCancelled, autoRefresh {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if !Task.isCancelled, autoRefresh, !isScanning {
                    scan(selected, clear: false)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            RemoteSensorEditor(sensor: editingSensor) { sensor in
                if let index = sensors.firstIndex(where: { $0.id == sensor.id }) {
                    sensors[index] = sensor
                } else {
                    sensors.append(sensor)
                }
                selectedID = sensor.id
                store.save(sensors)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            if sensors.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "server.rack")
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No sensors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(sensors) { sensor in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sensor.name).font(.caption.bold())
                            Text("\(sensor.username)@\(sensor.host)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .tag(sensor.id)
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            HStack {
                Button {
                    editingSensor = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add sensor")
                Button {
                    if let selected {
                        editingSensor = selected
                        showingEditor = true
                    }
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(selected == nil)
                .help("Edit sensor")
                Spacer()
                Button(role: .destructive) {
                    guard let selected else { return }
                    sensors.removeAll { $0.id == selected.id }
                    store.save(sensors)
                    selectedID = sensors.first?.id
                    results = []
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selected == nil)
                .help("Delete sensor")
                .accessibilityLabel("Delete sensor")
            }
            .buttonStyle(.borderless)
            .padding(7)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selected.name).font(.headline)
                        Text("ssh \(selected.username)@\(selected.host):\(selected.port)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Auto 60 s", isOn: $autoRefresh)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if isScanning {
                        ProgressView().controlSize(.small)
                    }
                    Button("Scan") { scan(selected) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isScanning)
                }
                .padding([.horizontal, .top], 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                }

                if results.isEmpty && !isScanning {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No remote scan yet")
                            .font(.headline)
                        Text("The sensor must have Remote Login enabled and your SSH key authorized.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(results) {
                        TableColumn("SSID", value: \.ssid)
                        TableColumn("Band", value: \.band).width(65)
                        TableColumn("Ch") { Text("\($0.channel)") }.width(35)
                        TableColumn("Width") { Text("\($0.widthMHz) MHz") }.width(60)
                        TableColumn("RSSI") { Text("\($0.rssi)").foregroundColor(rssiColor($0.rssi)) }.width(48)
                        TableColumn("SNR") { Text($0.snr.map(String.init) ?? "—") }.width(42)
                        TableColumn("PHY", value: \.phy)
                        TableColumn("Security", value: \.security)
                    }
                    .tableStyle(.inset)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("Add a remote sensor")
                    .font(.headline)
                Button("Add Sensor") {
                    editingSensor = nil
                    showingEditor = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func scan(_ sensor: RemoteSensor, clear: Bool = true) {
        if clear {
            errorMessage = nil
            results = []
        }
        isScanning = true
        Task {
            do {
                let scanned = try await Task.detached(priority: .userInitiated) {
                    try await RemoteSensorService.scan(sensor)
                }.value
                await MainActor.run {
                    isScanning = false
                    results = scanned
                    if scanned.isEmpty { errorMessage = "The sensor returned no wireless networks." }
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func rssiColor(_ rssi: Int) -> Color {
        switch rssi {
        case (-55)...: return .green
        case (-70)...: return .yellow
        default: return .red
        }
    }
}

private struct RemoteSensorEditor: View {
    @Environment(\.dismiss) private var dismiss
    let sensor: RemoteSensor?
    let onSave: (RemoteSensor) -> Void

    @State private var name: String
    @State private var host: String
    @State private var username: String
    @State private var port: String
    @State private var identityFile: String

    init(sensor: RemoteSensor?, onSave: @escaping (RemoteSensor) -> Void) {
        self.sensor = sensor
        self.onSave = onSave
        _name = State(initialValue: sensor?.name ?? "Remote Mac")
        _host = State(initialValue: sensor?.host ?? "")
        _username = State(initialValue: sensor?.username ?? NSUserName())
        _port = State(initialValue: String(sensor?.port ?? 22))
        _identityFile = State(initialValue: sensor?.identityFile ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sensor == nil ? "Add remote sensor" : "Edit remote sensor")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Name"); TextField("Office Mac", text: $name).frame(width: 260)
                }
                GridRow {
                    Text("Host"); TextField("192.168.1.20", text: $host).frame(width: 260)
                }
                GridRow {
                    Text("User"); TextField("username", text: $username).frame(width: 260)
                }
                GridRow {
                    Text("Port"); TextField("22", text: $port).frame(width: 80)
                }
                GridRow {
                    Text("SSH key")
                    TextField("~/.ssh/id_ed25519 (optional)", text: $identityFile).frame(width: 260)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    let sensor = RemoteSensor(
                        id: sensor?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Remote sensor" : name,
                        host: host.trimmingCharacters(in: .whitespaces),
                        username: username.trimmingCharacters(in: .whitespaces),
                        port: Int(port) ?? 22,
                        identityFile: identityFile.isEmpty ? nil : identityFile
                    )
                    onSave(sensor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || username.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}

private struct PollKey: Hashable {
    let id: UUID?
    let enabled: Bool
}
