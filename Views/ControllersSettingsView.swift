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
                    .disabled(selected == nil)
                }
                .buttonStyle(.borderless)
                .padding(6)
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
                    Table(aps) {
                        TableColumn("Name", value: \.name)
                        TableColumn("MAC", value: \.mac)
                        TableColumn("Model", value: \.model)
                        TableColumn("IP", value: \.ip)
                        TableColumn("Ch") { Text($0.channel.map(String.init) ?? "—") }.width(40)
                        TableColumn("Clients") { Text($0.clients.map(String.init) ?? "—") }.width(55)
                        TableColumn("TX") { Text($0.txPower.map { "\($0) dBm" } ?? "—") }.width(65)
                        TableColumn("Util.") { Text($0.utilization.map { "\($0)%" } ?? "—") }.width(55)
                        TableColumn("Channels") {
                            Text($0.supportedChannels.isEmpty ? "—" : "\($0.supportedChannels.count)")
                        }.width(65)
                    }
                } else {
                    Text("Add a UniFi or Meraki controller account.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(10)
        }
        .sheet(isPresented: $showingEditor) {
            ControllerEditor { account, token in
                accounts.append(account)
                ControllerKeychain.save(token, for: account.id)
                ControllerAccountStore().save(accounts)
                selectedID = account.id
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
        .padding(16)
        .frame(width: 440)
    }
}
