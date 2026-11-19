import LanFiCore
import SwiftUI

/// Settings → Toolkit. The toolkit shares one analysis target across every
/// probe screen, so its default value and its recent list are settings, not
/// screen state.
struct ToolkitSettingsPage: View {
    @ObservedObject private var target = AnalysisTarget.shared
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                targetCard
                historyCard
            }
            .padding(DesignToken.Spacing.large)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { draft = target.value }
    }

    private var targetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Text("Default analysis target")
                    .font(.headline)
                Text(
                    "Ping, Traceroute, MTR, DNS, GeoIP, Whois, Port Scan, TLS, Path Check and iperf3 share one address. It is filled in when you open a tool, and this field sets the value they start from."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DesignToken.Spacing.small) {
                    TextField("Host or IP address", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onSubmit { apply() }
                    Button("Apply") { apply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Clear") {
                        draft = ""
                        target.adopt("")
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.isEmpty)
                    Spacer()
                }
                if !target.value.isEmpty, target.value != draft {
                    Text("In use right now: \(target.value)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var historyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    Text("Recent targets")
                        .font(.headline)
                    Spacer()
                    Button("Clear history") { target.clearHistory() }
                        .buttonStyle(.bordered)
                        .disabled(target.history.isEmpty)
                }
                if target.history.isEmpty {
                    Text("Nothing yet. Run any probe tool and its address is kept here (five most recent).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(target.history, id: \.self) { value in
                        HStack(spacing: DesignToken.Spacing.small) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(value)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            Spacer()
                            Button("Use") {
                                draft = value
                                target.remember(value)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func apply() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        target.remember(trimmed)
        draft = trimmed
    }
}
