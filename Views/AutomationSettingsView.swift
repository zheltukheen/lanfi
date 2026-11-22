import LanFiCore
import SwiftUI

struct AutomationSettingsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var enabled = UserDefaults.standard.bool(forKey: AppSettingsKey.reportsEnabled.rawValue)
    @State private var minutes = max(UserDefaults.standard.integer(forKey: AppSettingsKey.reportsMinutes.rawValue), 15)
    @State private var folder = UserDefaults.standard.string(forKey: AppSettingsKey.reportsFolder.rawValue) ?? ""
    @State private var format = UserDefaults.standard.string(forKey: AppSettingsKey.reportsFormat.rawValue) ?? "CSV"

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
                Picker("Format", selection: $format) {
                    Text("CSV").tag("CSV")
                    Text("PDF").tag("PDF")
                    Text("Combined HTML").tag("Combined HTML")
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
                    UserDefaults.standard.set(enabled, forKey: AppSettingsKey.reportsEnabled.rawValue)
                    UserDefaults.standard.set(minutes, forKey: AppSettingsKey.reportsMinutes.rawValue)
                    UserDefaults.standard.set(folder, forKey: AppSettingsKey.reportsFolder.rawValue)
                    UserDefaults.standard.set(format, forKey: AppSettingsKey.reportsFormat.rawValue)
                    viewModel.configureScheduledReports()
                }
                Button("Write report now") {
                    viewModel.writeScheduledReport()
                }
                .disabled(folder.isEmpty)
            }
            Section {
                Text(
                    "Reports write the current scan (CSV/PDF) or the combined handover report (HTML with the latest survey, speed history and monitor events) while LanFi is running. macOS does not run this timer when the app is closed."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(DesignToken.Spacing.medium)
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
