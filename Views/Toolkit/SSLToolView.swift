import AppKit
import SwiftUI

struct SSLToolView: View {
    @ObservedObject var model: SSLToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let report = model.report {
                    summary(report)
                    chainTable(report)
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "lock.shield",
                        title: "Inspect a certificate",
                        message:
                            "Reads the server certificate chain, its issuer and validity dates without sending application data."
                    )
                }
            }
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                TextField("Host", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                TextField("Port", text: $model.portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Spacer()
                Button("Inspect") { model.run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)
                Button("Copy") { copy() }
                    .buttonStyle(.bordered)
                    .disabled(model.report == nil)
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .disabled(model.report == nil)
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Handshaking…") }
        guard let report = model.report else { return String(localized: "Ready") }
        if report.expired { return "Expired" }
        return report.trusted ? "Trusted" : "Untrusted"
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard let report = model.report else { return .neutral }
        if report.expired { return .bad }
        return report.trusted ? .good : .warning
    }

    private func summary(_ report: TLSCertificateReport) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: report.expired ? "xmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 34))
                    .foregroundColor(report.expired ? .red : (report.trusted ? .green : .orange))
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.trusted ? "Certificate chain is trusted" : "Certificate chain is not trusted")
                        .font(.headline)
                    Text(
                        "\(report.host):\(report.port) · \(report.certificates.count) certificate\(report.certificates.count == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    if let days = report.daysRemaining {
                        Text(days >= 0 ? "\(days) days until expiry" : "Expired \(-days) days ago")
                            .font(.caption.weight(.medium))
                            .foregroundColor(report.expired ? .red : (report.expiresSoon ? .orange : .secondary))
                    }
                }
                Spacer()
            }
        }
    }

    private func chainTable(_ report: TLSCertificateReport) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Chain")
                    Spacer()
                    Text("Checked \(report.checkedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(report.certificates) {
                    TableColumn("Subject") { certificate in
                        Text(certificate.subject)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    TableColumn("Issuer") { certificate in
                        Text(certificate.issuer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    TableColumn("Not before") { certificate in
                        Text(ToolkitFormat.date(certificate.notBefore))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(110)
                    TableColumn("Not after") { certificate in
                        Text(ToolkitFormat.date(certificate.notAfter))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(110)
                }
                .frame(height: min(CGFloat(report.certificates.count) * 26 + 28, 360))
            }
        }
    }

    private func copy() {
        guard let report = model.report else { return }
        var lines = [
            "LanFi TLS \(report.host):\(report.port)",
            "Trusted: \(report.trusted)",
            "Days remaining: \(report.daysRemaining.map(String.init) ?? "-")",
            "",
        ]
        for certificate in report.certificates {
            lines.append(
                "\(certificate.subject)\t\(certificate.issuer)\t\(ToolkitFormat.date(certificate.notBefore))\t\(ToolkitFormat.date(certificate.notAfter))"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
