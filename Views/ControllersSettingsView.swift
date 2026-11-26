import PostHog
import SwiftUI

struct ControllersSettingsView: View {
    @State private var accounts: [ControllerAccount] = ControllerAccountStore().load()
    @State private var selectedID: UUID?
    @State private var aps: [ControllerAccessPoint] = []
    @State private var errorMessage: String?
    @State private var loading = false
    @State private var showingEditor = false

    private var selected: ControllerAccount? { accounts.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            VStack {
                List(selection: $selectedID) {
                    ForEach(accounts) { account in
                        VStack(alignment: .leading) {
                            Text(account.name).font(.caption.bold())
                            Text(account.kind.title).font(.caption2).foregroundColor(.secondary)
                        }
                        .tag(account.id)
                    }
                }
                HStack {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add controller")
                    .accessibilityLabel("Add controller")
                    Button(role: .destructive) {
                        if let selected {
                            accounts.removeAll { $0.id == selected.id }
                            ControllerKeychain.delete(for: selected.id)
                            ControllerAccountStore().save(accounts)
                            selectedID = accounts.first?.id
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete controller account")
                    .disabled(selected == nil)
                }
                .buttonStyle(.borderless)
                .padding(DesignToken.Spacing.tight)
            }
            .frame(minWidth: 200)

            VStack(alignment: .leading, spacing: 8) {
                if let selected {
                    HStack {
                        Text(selected.name).font(.headline)
                        Spacer()
                        Button("Fetch APs") { fetch(selected) }
                            .disabled(loading)
                        if loading { ProgressView().controlSize(.small) }
                    }
                    Text("\(selected.kind.title) · \(selected.baseURL) · \(selected.siteOrOrg)")
                        .font(.caption2).foregroundColor(.secondary)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundColor(.red).textSelection(.enabled)
                    }
                    HStack {
                        Spacer()
                    }
                    AppTable(
                        columns: [
                            AppTableColumn(
                                id: "name", title: "Name", minWidth: 120,
                                value: { .text($0.name) }
                            ) { Text($0.name) },
                            AppTableColumn(
                                id: "mac", title: "MAC", minWidth: 120,
                                value: { .text($0.mac) }
                            ) { Text($0.mac).font(.caption.monospaced()) },
                            AppTableColumn(
                                id: "model", title: "Model", minWidth: 110,
                                value: { .text($0.model) }
                            ) { Text($0.model) },
                            AppTableColumn(
                                id: "ip", title: "IP", minWidth: 100,
                                value: { .text($0.ip) }
                            ) { Text($0.ip).font(.caption.monospaced()) },
                            AppTableColumn(
                                id: "channel", title: "Ch", minWidth: 36,
                                value: { .number($0.channel) }
                            ) { Text($0.channel.map(String.init) ?? "—") },
                            AppTableColumn(
                                id: "clients", title: "Clients", minWidth: 50,
                                value: { .number($0.clients) }
                            ) { Text($0.clients.map(String.init) ?? "—") },
                            AppTableColumn(
                                id: "tx", title: "TX", minWidth: 60,
                                value: { .number($0.txPower) }
                            ) { Text($0.txPower.map { "\($0) dBm" } ?? "—") },
                            AppTableColumn(
                                id: "utilization", title: "Util.", minWidth: 50,
                                value: { .number($0.utilization) }
                            ) { Text($0.utilization.map { "\($0)%" } ?? "—") },
                            AppTableColumn(
                                id: "channels", title: "Channels", minWidth: 60,
                                value: { .number($0.supportedChannels.count) }
                            ) { ap in
                                Text(
                                    ap.supportedChannels.isEmpty
                                        ? "—" : "\(ap.supportedChannels.count)")
                            },
                        ],
                        rows: aps, initialKey: "name")
                } else {
                    Text("Add a UniFi or Meraki controller account.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(DesignToken.Spacing.compact)
        }
        .sheet(isPresented: $showingEditor) {
            ControllerEditor { account, token in
                accounts.append(account)
                ControllerKeychain.save(token, for: account.id)
                ControllerAccountStore().save(accounts)
                selectedID = account.id
                PostHogSDK.shared.capture(
                    "controller_added",
                    properties: ["controller_type": account.kind.title])
            }
        }
    }

    private func fetch(_ account: ControllerAccount) {
        loading = true
        errorMessage = nil
        aps = []
        Task {
            do {
                let result = try await ControllerService.fetchAccessPoints(account)
                for ap in result {
                    ChannelPlanCache.update(mac: ap.mac, channels: ap.supportedChannels)
                }
                await MainActor.run {
                    loading = false
                    aps = result
                    PostHogSDK.shared.capture(
                        "controller_access_points_fetched",
                        properties: [
                            "controller_type": account.kind.title,
                            "access_point_count": result.count,
                        ])
                }
            } catch {
                await MainActor.run {
                    loading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ControllerEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ControllerAccount, String) -> Void
    @State private var kind: ControllerKind = .unifi
    @State private var name = ""
    @State private var baseURL = "https://"
    @State private var site = "default"
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controller account").font(.headline)
            Picker("Type", selection: $kind) { ForEach(ControllerKind.allCases) { Text($0.title).tag($0) } }
            TextField("Name", text: $name)
            TextField("Base URL", text: $baseURL)
            TextField(kind == .unifi ? "Site" : kind == .meraki ? "Organization ID" : "OID", text: $site)
            SecureField(kind == .snmp ? "Community" : "API token", text: $token)
            Text(
                kind == .unifi
                    ? "Uses UniFi API key with X-API-KEY."
                    : kind == .meraki
                        ? "Uses Meraki dashboard API key."
                        : "Runs /usr/bin/snmpwalk -v2c against the host and OID."
            )
            .font(.caption2).foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    let account = ControllerAccount.new(
                        kind: kind, name: name.isEmpty ? kind.title : name,
                        baseURL: baseURL, siteOrOrg: site
                    )
                    onSave(account, token)
                    dismiss()
                }
                .disabled(name.isEmpty || baseURL.isEmpty || token.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(DesignToken.Spacing.large)
        .frame(width: 440)
    }
}
