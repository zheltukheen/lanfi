import AppKit
import SwiftUI

/// Settings for the Model Context Protocol server that ships with the CLI.
/// The app itself never speaks MCP: it publishes the live scan for the
/// `lanfi-cli mcp` process, and this screen makes that hand-off visible.
struct MCPSettingsView: View {
    @AppStorage("LanFi.mcp.publishSnapshot") private var publishSnapshot = true
    @AppStorage("LanFi.mcp.clientName") private var clientName = "lanfi"
    @AppStorage("LanFi.mcp.cliPath") private var storedCLIPath = ""

    @State private var copiedConfig = false
    @State private var copiedPath = false

    private var cliPath: String {
        let trimmed = storedCLIPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MCPSettings.defaultCLIPath : trimmed
    }

    private var snapshotPath: String { MCPPaths.liveSnapshotURL.path }

    private var configuration: String {
        let resolvedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let object: [String: Any] = [
            "mcpServers": [
                (resolvedName.isEmpty ? "lanfi" : resolvedName): [
                    "command": cliPath,
                    "args": ["mcp"],
                ]
            ]
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    var body: some View {
        Form {
            Section("Live scan snapshot") {
                Toggle("Publish the latest scan for MCP clients", isOn: $publishSnapshot)
                LabeledContent("Snapshot file") {
                    Text(snapshotPath)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([MCPPaths.liveSnapshotURL])
                    }
                    Button(copiedPath ? "Copied" : "Copy path") {
                        copy(snapshotPath)
                        copiedPath = true
                    }
                }
                Text(
                    "LanFi rewrites this file at most every five seconds while it runs. Agents read it without Location access or a second Wi-Fi scan. Turning this off leaves the file untouched."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Section("MCP client") {
                TextField("lanfi-cli path", text: $storedCLIPath, prompt: Text(cliPath))
                    .font(.caption.monospaced())
                HStack {
                    Button("Detect") { storedCLIPath = MCPSettings.detectCLIPath() ?? cliPath }
                    Button("Use default") { storedCLIPath = MCPSettings.defaultCLIPath }
                    Spacer()
                    Label(
                        FileManager.default.isExecutableFile(atPath: cliPath)
                            ? "Found" : "Not found",
                        systemImage: FileManager.default.isExecutableFile(atPath: cliPath)
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundColor(
                        FileManager.default.isExecutableFile(atPath: cliPath) ? .green : .orange)
                }
                TextField("Client name", text: $clientName)
                    .font(.caption)

                Text(
                    "Add this block to the MCP configuration of Claude Desktop, Claude Code, Cursor or another client:"
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                Text(configuration)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                Button(copiedConfig ? "Copied" : "Copy client configuration") {
                    copy(configuration)
                    copiedConfig = true
                }
            }

            Section("What agents can do") {
                Text(
                    "The server exposes scan analysis, channel and protocol recommendations, ping, traceroute, MTR, port and path checks, DNS, WHOIS, GeoIP, TLS, subnet, interfaces, routes, LAN discovery, the Device Shelf, uptime, diagnostics and speed tests."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                Button("Open MCP documentation") {
                    if let url = URL(
                        string: "https://github.com/zheltukheen/lanfi/blob/main/docs/mcp.md")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text(
                    "The server runs over stdio, stays on this Mac and never uploads scan data."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum MCPSettings {
    static var defaultCLIPath: String {
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("lanfi-cli").path,
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/lanfi-cli").path,
            "/opt/homebrew/bin/lanfi-cli",
            "/usr/local/bin/lanfi-cli",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/lanfi-cli"
    }

    static func detectCLIPath() -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("lanfi-cli").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
