import SwiftUI

struct ComingSoonToolView: View {
    let tool: ToolboxTool

    var body: some View {
        ScrollView {
            ToolkitCard {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 38))
                        .foregroundColor(.secondary)
                        .frame(width: 46)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tool.title)
                            .font(.title3.bold())
                        Text(tool.plannedDetail)
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("Planned for a later phase. The probe layer and the window are in place.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ToolkitStatusPill(text: "Planned", tone: .neutral)
                }
                .padding(4)
            }
        }
        .padding(18)
    }
}

struct WiFiRedirectToolView: View {
    let tool: ToolboxTool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            ToolkitCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 38))
                            .foregroundColor(.accentColor)
                            .frame(width: 46)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tool.title)
                                .font(.title3.bold())
                            Text(
                                "The full \(tool == .wifiAnalyzer ? "analyzer" : "network list") lives in the main LanFi window, where the scan table, insights, spectrum and survey already are."
                            )
                            .font(.callout)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    Button {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Label("Open LanFi", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(18)
    }
}
