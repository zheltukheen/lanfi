import SwiftUI

struct AutomationSettingsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var enabled = UserDefaults.standard.bool(forKey: "Wifa.reports.enabled")
    @State private var minutes = max(UserDefaults.standard.integer(forKey: "Wifa.reports.minutes"), 15)
    @State private var folder = UserDefaults.standard.string(forKey: "Wifa.reports.folder") ?? ""

    var body: some View {
        Form {
            Section("Scheduled reports") {
                Toggle("Enable scheduled reports", isOn: $enabled)
                Picker("Interval", selection: $minutes) {
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("60 minutes").tag(60)
                }
                HStack {
                    Text(folder.isEmpty ? "No folder selected" : folder)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                }
                Button("Save settings") {
                    UserDefaults.standard.set(enabled, forKey: "Wifa.reports.enabled")
                    UserDefaults.standard.set(minutes, forKey: "Wifa.reports.minutes")
                    UserDefaults.standard.set(folder, forKey: "Wifa.reports.folder")
                    viewModel.configureScheduledReports()
                }
                Button("Write report now") {
                    viewModel.writeScheduledReport()
                }
                .disabled(folder.isEmpty)
            }
            Section {
                Text(
                    "Reports use the currently visible columns and write a CSV snapshot while LanFi is running. macOS does not run this timer when the app is closed."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }
}
