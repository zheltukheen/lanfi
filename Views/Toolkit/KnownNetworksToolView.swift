import AppKit
import SwiftUI

/// Read-only inventory of networks saved in System Settings, with an on-demand
/// guest QR code. LanFi never reads or stores Wi-Fi passwords: the password in
/// the QR sheet is typed by the user and only used to build the payload.
struct KnownNetworksToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel

    @State private var networks: [KnownNetwork] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shareTarget: KnownNetwork?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task { await load() }
        .sheet(item: $shareTarget) { network in
            KnownNetworkQRSheet(
                ssid: network.ssid,
                suggestedSecurity: security(for: network.ssid))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(networks.count) saved networks")
                    .font(.callout.weight(.semibold))
                Text("Read-only: names come from System Settings. Passwords are never read.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await load() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ToolkitErrorBanner(message: errorMessage)
                .padding(18)
            Spacer()
        } else if networks.isEmpty {
            ToolkitEmptyState(
                icon: "wifi.router",
                title: "No saved networks",
                message:
                    "Join a network in System Settings and reload. LanFi lists saved names only and cannot show or export their passwords."
            )
            Spacer()
        } else {
            Table(networks) {
                TableColumn("Network") { network in
                    Text(network.ssid).font(.callout)
                }
                TableColumn("Now") { network in
                    if let match = matched(network.ssid) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppPalette.band(match.band))
                                .frame(width: 6, height: 6)
                            Text("\(match.bandLabel) · Ch \(match.channel) · \(match.signal) dBm")
                                .font(.caption2)
                        }
                    } else {
                        Text("Not in range")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                TableColumn("Security") { network in
                    Text(matched(network.ssid)?.security ?? "—")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                TableColumn("") { network in
                    Button {
                        shareTarget = network
                    } label: {
                        Label("QR", systemImage: "qrcode")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Create a guest QR code for this network")
                }
                .width(56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func matched(_ ssid: String) -> NetworkModel? {
        analyzer.networks
            .filter { $0.ssid == ssid }
            .max { $0.signal < $1.signal }
    }

    private func security(for ssid: String) -> WiFiQRPayload.Security {
        let value = matched(ssid)?.security.lowercased() ?? ""
        if value.contains("open") || value.contains("none") { return .open }
        if value.contains("wep") { return .wep }
        return .wpa
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let names = await Task.detached(priority: .userInitiated) {
            KnownNetworksService().preferredNetworks()
        }.value
        networks = names
        if names.isEmpty {
            errorMessage =
                "macOS returned no saved networks. This can happen when Wi-Fi is off or System Settings has no preferred networks."
        }
        isLoading = false
    }
}

private struct KnownNetworkQRSheet: View {
    let ssid: String
    let suggestedSecurity: WiFiQRPayload.Security

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var security: WiFiQRPayload.Security = .wpa
    @State private var didCopy = false

    private var payload: String {
        WiFiQRPayload.string(ssid: ssid, password: password, security: security)
    }

    private var image: NSImage? {
        QRCode.image(for: payload, scale: 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guest QR code").font(.title3.bold())
            Text(
                "The password is only used to build this code. LanFi does not store it and cannot read the saved password from System Settings."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Network").font(.caption).foregroundColor(.secondary)
                    Text(ssid).font(.callout).textSelection(.enabled)
                }
                GridRow {
                    Text("Security").font(.caption).foregroundColor(.secondary)
                    Picker("Security", selection: $security) {
                        ForEach(WiFiQRPayload.Security.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                GridRow {
                    Text("Password").font(.caption).foregroundColor(.secondary)
                    SecureField("Network password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(security == .open)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                if let image {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .frame(width: 180, height: 180)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("QR generation failed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Payload").font(.caption2).foregroundColor(.secondary)
                    Text(payload)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(4)
                    Button(didCopy ? "Copied" : "Copy payload") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload, forType: .string)
                        didCopy = true
                    }
                    .controlSize(.small)
                    .disabled(security != .open && password.isEmpty)
                }
                Spacer()
            }
            .padding(.top, 4)

            HStack {
                Button("Close") { dismiss() }
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}
