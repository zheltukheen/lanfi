import AppKit
import SwiftUI

struct GeoIPToolView: View {
    @ObservedObject var model: GeoIPToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let report = model.report {
                    header(report)
                    HStack(alignment: .top, spacing: 12) {
                        locationCard(report)
                        networkCard(report)
                    }
                    coordinatesCard(report)
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "globe",
                        title: "Locate an IP address",
                        message:
                            "Type an IP or hostname, or use My IP. Hostnames are resolved locally first; only the address is sent to ipwho.is."
                    )
                }
            }
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                TextField("IP address or hostname", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { model.run() }
                Button("Look Up") { model.run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)
                Button {
                    model.run(myIP: true)
                } label: {
                    Label("My IP", systemImage: "location")
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning)
                Button("Copy") { copy() }
                    .buttonStyle(.bordered)
                    .disabled(model.report == nil)
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .disabled(model.report == nil)
                Spacer()
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Looking up…") }
        guard let report = model.report else { return String(localized: "Ready") }
        return report.countryCode.isEmpty ? report.ip : "\(report.countryCode) · \(report.ip)"
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        return model.report == nil ? .neutral : .good
    }

    private func header(_ report: GeoIPReport) -> some View {
        ToolkitCard {
            HStack(spacing: 12) {
                Text(report.flagEmoji)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.locationLine.isEmpty ? report.ip : report.locationLine)
                        .font(.title3.bold())
                    Text("\(report.ip) · \(report.type)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                if report.query == "My IP" {
                    ToolkitStatusPill(text: "This Mac", tone: .good)
                }
            }
        }
    }

    private func locationCard(_ report: GeoIPReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Location")
                detail("City", report.city)
                detail("Region", report.region)
                detail("Country", "\(report.country) (\(report.countryCode))")
                detail("Continent", report.continent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func networkCard(_ report: GeoIPReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Network")
                detail("ASN", report.asn.map { "AS\($0)" } ?? "—")
                detail("Organization", report.organization)
                detail("ISP", report.isp)
                detail("Timezone", "\(report.timezone) \(report.utcOffset)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func coordinatesCard(_ report: GeoIPReport) -> some View {
        ToolkitCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    ToolkitSectionLabel(text: "Coordinates")
                    Text(report.coordinateText)
                        .font(.callout.monospacedDigit())
                }
                Spacer()
                Button {
                    openInMaps(report)
                } label: {
                    Label("Open in Maps", systemImage: "map")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func openInMaps(_ report: GeoIPReport) {
        guard
            let url = URL(
                string:
                    "https://maps.apple.com/?ll=\(report.latitude),\(report.longitude)&q=\(report.ip)"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func copy() {
        guard let report = model.report else { return }
        let text = """
            LanFi GeoIP \(report.query)
            IP: \(report.ip)
            Location: \(report.locationLine)
            Country: \(report.country) (\(report.countryCode))
            ASN: \(report.asn.map { "AS\($0)" } ?? "—")
            Organization: \(report.organization)
            ISP: \(report.isp)
            Coordinates: \(report.coordinateText)
            Timezone: \(report.timezone) \(report.utcOffset)
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
