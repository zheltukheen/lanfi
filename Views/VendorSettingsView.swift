import SwiftUI

struct SettingsView: View {
    @State private var prefix = ""
    @State private var vendor = ""
    @State private var overrides = OUIParser.customOverrides()
    @State private var isUpdating = false
    @State private var status: String?
    @State private var errorMessage: String?
    @State private var lastUpdated = OUIUpdater.lastUpdated

    var body: some View {
        Form {
            Section("Menu bar alerts") {
                Toggle(
                    "Weak Wi-Fi signal",
                    isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "Wifa.alerts.weakSignal") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "Wifa.alerts.weakSignal") }
                    ))
                Toggle(
                    "Open networks visible",
                    isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "Wifa.alerts.openNetwork") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "Wifa.alerts.openNetwork") }
                    ))
                Toggle(
                    "Connected channel changes",
                    isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "Wifa.alerts.channelChange") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "Wifa.alerts.channelChange") }
                    ))
            }

            Section("Wi-Fi adapter") {
                Picker(
                    "Scan interface",
                    selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "Wifa.wifiInterface") ?? "" },
                        set: { UserDefaults.standard.set($0.isEmpty ? nil : $0, forKey: "Wifa.wifiInterface") }
                    )
                ) {
                    Text("System default").tag("")
                    ForEach(WiFiInterfaceCatalog.names(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Text("External USB Wi-Fi adapters appear here when macOS exposes them through CoreWLAN.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Vendor database") {
                LabeledContent("Bundled + downloaded") {
                    Text(lastUpdated.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Bundled only")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button {
                        updateDatabase()
                    } label: {
                        if isUpdating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Update from Wireshark", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isUpdating)
                    if let status {
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
            }

            Section("Custom OUI overrides") {
                HStack {
                    TextField("Prefix (6–9 hex)", text: $prefix)
                        .frame(width: 140)
                    TextField("Vendor name", text: $vendor)
                    Button("Add") {
                        guard OUIParser.setOverride(prefix: prefix, vendor: vendor) else {
                            errorMessage = "Prefix must be 6–9 hex characters and vendor must not be empty."
                            return
                        }
                        overrides = OUIParser.customOverrides()
                        prefix = ""
                        vendor = ""
                        errorMessage = nil
                    }
                }
                ForEach(overrides.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key).font(.system(.caption, design: .monospaced))
                        Text(value).font(.caption)
                        Spacer()
                        Button(role: .destructive) {
                            OUIParser.removeOverride(key)
                            overrides = OUIParser.customOverrides()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove OUI override")
                    }
                }
            }

            Section {
                Text("Overrides are stored locally and win over the downloaded database.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 560, height: 460)
        .onAppear { overrides = OUIParser.customOverrides() }
    }

    private func updateDatabase() {
        isUpdating = true
        errorMessage = nil
        status = nil
        Task {
            do {
                let date = try await OUIUpdater.update()
                await MainActor.run {
                    isUpdating = false
                    lastUpdated = date
                    status = "Updated"
                }
            } catch {
                await MainActor.run {
                    isUpdating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
