import LanFiCore
import Foundation
import SwiftUI

/// The one address the user is investigating.
///
/// Every host/domain field in the toolkit binds its text through
/// `ToolTargetField`, so a value typed in Ping is already filled in when the
/// user opens Traceroute, MTR, GeoIP, Whois, DNS, TLS, Port Scan, Path Check or
/// iperf3. The last five distinct values are offered from the field's history
/// menu and persist across launches.
@MainActor
final class AnalysisTarget: ObservableObject {
    static let shared = AnalysisTarget()

    @Published var value: String {
        didSet { defaults.set(value, forKey: AppSettingsKey.toolkitTarget.rawValue) }
    }
    @Published private(set) var history: [String]

    private let defaults = UserDefaults.standard
    private static let historyLimit = 5

    private init() {
        let defaults = UserDefaults.standard
        value = defaults.string(forKey: AppSettingsKey.toolkitTarget.rawValue) ?? ""
        history =
            defaults.stringArray(forKey: AppSettingsKey.toolkitTargetHistory.rawValue) ?? []
    }

    /// Updates the shared value without recording history (used while typing).
    func adopt(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value else { return }
        value = trimmed
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: AppSettingsKey.toolkitTargetHistory.rawValue)
    }

    /// Records a value that was actually submitted or picked from the menu.
    func remember(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        value = trimmed
        history.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        history.insert(trimmed, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        defaults.set(history, forKey: AppSettingsKey.toolkitTargetHistory.rawValue)
    }
}

/// Host/domain field shared by every probe screen, with a history menu.
struct ToolTargetField: View {
    @ObservedObject private var target = AnalysisTarget.shared
    @Binding var text: String
    var placeholder: String = "Host or IP address"
    var maxWidth: CGFloat = 280
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: maxWidth)
                .onSubmit {
                    target.remember(text)
                    onSubmit()
                }
            Menu {
                if target.history.isEmpty {
                    Text("No recent addresses")
                } else {
                    ForEach(target.history, id: \.self) { item in
                        Button(item) {
                            text = item
                            target.remember(item)
                        }
                    }
                    Divider()
                    Button("Clear history") { clearHistory() }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Recent addresses")
            .accessibilityLabel("Recent addresses")
        }
        .onAppear {
            if !target.value.isEmpty, target.value != text { text = target.value }
        }
        .onChange(of: target.value) { value in
            if !value.isEmpty, value != text { text = value }
        }
    }

    private var binding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = newValue
                // Live propagation: switching tools keeps the half-typed host.
                target.adopt(newValue)
            })
    }

    private func clearHistory() {
        target.clearHistory()
    }
}
