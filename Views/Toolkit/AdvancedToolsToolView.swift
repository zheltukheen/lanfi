import AppKit
import SwiftUI

/// Specialised system tools that used to open their own Tool window. They now
/// live in the toolkit and run in-place; external apps are plain links.
struct AdvancedToolsToolView: View {
    @State private var selectedID = ToolCatalog.all.first?.id ?? "custom"

    private var selected: DiagnosticTool? {
        ToolCatalog.tool(id: selectedID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            ToolConsoleView(toolID: selectedID)
                .id(selectedID)
            externalLinks
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                Text("Tool")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Tool", selection: $selectedID) {
                    ForEach(ToolCatalog.all) { tool in
                        Label(tool.title, systemImage: tool.icon).tag(tool.id)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                if let selected {
                    Text(selected.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var externalLinks: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "External tools")
                HStack(spacing: 14) {
                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "https://github.com/halo/LinkLiar/releases")!)
                    } label: {
                        Label("LinkLiar — MAC address spoofer…", systemImage: "link")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "https://www.wireshark.org/download.html")!)
                    } label: {
                        Label("Wireshark…", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .font(.caption)
            }
        }
    }
}
