import SwiftUI

struct SurveyReportSettingsView: View {
    @ObservedObject var survey: SurveyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var client = ""
    @State private var planWidth = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Survey report").font(.headline)
            Form {
                TextField("Report title", text: $title)
                TextField("Client / site", text: $client)
                TextField("Plan width in metres", text: $planWidth)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    survey.updateReportMetadata(
                        title: title, client: client, planWidth: planWidth, notes: notes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            title = survey.project.reportTitle ?? ""
            client = survey.project.clientName ?? ""
            planWidth = survey.project.planWidthMeters.map { String(format: "%.1f", $0) } ?? ""
            notes = survey.project.reportNotes ?? ""
        }
    }
}
