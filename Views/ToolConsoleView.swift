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
    @State private var isInstalling = false
    @State private var installSucceeded: Bool?
    @State private var installOutput: String?

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
                if executable == nil {
                    installBanner(tool)
                }
                HStack {
                    Text(executable ?? String(localized: "Not found"))
                        .font(.caption.monospaced()).lineLimit(1)
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
                        Text(
                            String(
                                format: String(localized: "Last run %@"),
                                startedAt.formatted(date: .omitted, time: .standard))
                        )
                        .font(.caption2)
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

    @ViewBuilder
    private func installBanner(_ tool: DiagnosticTool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tool.title) is not installed")
                        .font(.caption.weight(.semibold))
                    if let hint = tool.installHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if let package = tool.brewPackage {
                    if isInstalling {
                        ProgressView().controlSize(.small)
                        Text("Installing…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Button {
                            install(package)
                        } label: {
                            Label(
                                installSucceeded == false ? "Try Again" : "Install",
                                systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button("Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            ToolInstaller.command(for: package), forType: .string)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
            }
            if let installOutput, !installOutput.isEmpty {
                Text(installOutput)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(installSucceeded == true ? .secondary : .orange)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func install(_ package: String) {
        guard !isInstalling else { return }
        isInstalling = true
        installSucceeded = nil
        installOutput = nil
        Task {
            let result = await ToolInstaller.install(package: package)
            await MainActor.run {
                isInstalling = false
                installSucceeded = result.succeeded
                installOutput = result.message
                if let tool {
                    executable = ToolRunner.locate(tool.candidates)
                }
            }
        }
    }

    private func run() {
        guard let executable else { return }
        running = true
        output = String(localized: "Running…")
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
