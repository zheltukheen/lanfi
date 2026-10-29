import SwiftUI
import UniformTypeIdentifiers

struct ToolConsoleView: View {
    let toolID: String
    @State private var tool: DiagnosticTool?
    @State private var executable: String?
    @State private var arguments = ""
    @State private var output = ""
    @State private var running = false
    @State private var startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let tool {
                HStack {
                    Label(tool.title, systemImage: tool.icon).font(.title3.bold())
                    Spacer()
                    Text(tool.category).font(.caption).foregroundColor(.secondary)
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Toggle full screen")
                }
                Text(tool.description).font(.caption).foregroundColor(.secondary)
                if let installHint = tool.installHint, executable == nil {
                    Text(installHint).font(.caption).foregroundColor(.orange).textSelection(.enabled)
                }
                HStack {
                    Text(executable ?? "Not found").font(.caption.monospaced()).lineLimit(1)
                    Spacer()
                    Button("Run") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(running || executable == nil)
                    if running { ProgressView().controlSize(.small) }
                }
                TextField("Arguments", text: $arguments)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                HStack {
                    Button("Copy output") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                    }
                    .disabled(output.isEmpty)
                    Button("Save…") { save() }
                        .disabled(output.isEmpty)
                    Spacer()
                    if let startedAt {
                        Text("Last run \(startedAt.formatted(date: .omitted, time: .standard))").font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .controlSize(.small)
                ScrollView {
                    Text(output.isEmpty ? "Run the tool to see output." : output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Unknown tool").foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 520)
        .onAppear {
            tool = ToolCatalog.tool(id: toolID)
            if let tool {
                executable = ToolRunner.locate(tool.candidates)
                arguments = tool.arguments.joined(separator: " ")
            }
        }
    }

    private func run() {
        guard let executable else { return }
        running = true
        output = "Running…"
        startedAt = Date()
        let args = parseArguments(arguments)
        Task {
            let text = await ToolRunner.run(executable: executable, arguments: args)
            await MainActor.run {
                output = text
                running = false
            }
        }
    }

    private func parseArguments(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in value {
            if character == "\"" {
                quoted.toggle()
            } else if character == " " && !quoted {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-\(toolID).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }
}
