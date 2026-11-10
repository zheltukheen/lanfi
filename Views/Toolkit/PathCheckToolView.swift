import SwiftUI

struct PathCheckToolView: View {
    @ObservedObject var model: PathCheckToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let outcome = model.outcome {
                    result(outcome)
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "arrow.triangle.branch",
                        title: "Check a host and port",
                        message:
                            "A TCP connect probe tells you whether a service is reachable from this Mac, without traceroute privileges."
                    )
                }
            }
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                TextField("example.com:443", text: $model.target)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { model.run() }
                Button("Check") { model.run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .disabled(model.outcome == nil)
                Spacer()
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Connecting…") }
        guard let outcome = model.outcome else { return String(localized: "Ready") }
        switch outcome {
        case .open: return "Reachable"
        case .closed: return "Refused"
        case .filtered: return "No response"
        }
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard let outcome = model.outcome else { return .neutral }
        switch outcome {
        case .open: return .good
        case .closed: return .bad
        case .filtered: return .warning
        }
    }

    private func result(_ outcome: TCPProbeOutcome) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon(for: outcome))
                    .font(.system(size: 36))
                    .foregroundColor(color(for: outcome))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(for: outcome))
                        .font(.title3.bold())
                    Text(detail(for: outcome))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    if let milliseconds = milliseconds(for: outcome) {
                        Text(String(format: "TCP handshake: %.1f ms", milliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func icon(for outcome: TCPProbeOutcome) -> String {
        switch outcome {
        case .open: return "checkmark.circle.fill"
        case .closed: return "xmark.circle.fill"
        case .filtered: return "questionmark.circle.fill"
        }
    }

    private func color(for outcome: TCPProbeOutcome) -> Color {
        switch outcome {
        case .open: return .green
        case .closed: return .red
        case .filtered: return .orange
        }
    }

    private func title(for outcome: TCPProbeOutcome) -> String {
        switch outcome {
        case .open: return "The port is reachable"
        case .closed: return "The host refused the connection"
        case .filtered: return "No response"
        }
    }

    private func detail(for outcome: TCPProbeOutcome) -> String {
        switch outcome {
        case .open:
            return "A TCP handshake completed, so a service is listening on this address and port."
        case .closed(_, let detail):
            return detail ?? "The host answered, but nothing is listening on this port."
        case .filtered(let detail):
            return detail ?? "A firewall or the host dropped the probe before the timeout."
        }
    }

    private func milliseconds(for outcome: TCPProbeOutcome) -> Double? {
        switch outcome {
        case .open(let milliseconds): return milliseconds
        case .closed(let milliseconds, _): return milliseconds
        case .filtered: return nil
        }
    }
}
