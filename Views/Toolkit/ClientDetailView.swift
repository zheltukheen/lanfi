import AppKit
import LanFiCore
import SwiftUI

/// G8: one captured client — identity, advertised capabilities and a live
/// signal locator. The locator follows the BSSID the client was seen on: macOS
/// will not stream a single client's RSSI without a privileged monitor capture,
/// so the reading describes the AP the client talks to, not the client itself.
/// That limitation is stated in the card rather than hidden.
struct ClientDetailView: View {
    let observation: ClientObservation
    let network: NetworkModel?

    @Environment(\.dismiss) private var dismiss
    @State private var locator = SignalLocator()
    @State private var history: [Int] = []
    @State private var isLocating = false
    @State private var pingOnRise = false
    @State private var statusMessage: String?

    private var bssid: String { observation.bssid }
    private var canLocate: Bool { !bssid.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                    identityCard
                    capabilitiesCard
                    locatorCard
                }
            }
        }
        .appSheet(width: DesignToken.Layout.sheetWidthWide, minHeight: 520)
        .task(id: isLocating) { await runLocator() }
        .onDisappear { isLocating = false }
    }

    private var header: some View {
        AppSheetHeader(
            icon: "person.crop.circle",
            title: LocalizedStringKey(displayName),
            subtitle: "Captured client \(observation.mac)"
        ) {
            Button("Close") { dismiss() }
        }
    }

    private var displayName: String {
        observation.vendor.isEmpty || observation.vendor == "Unknown"
            ? observation.mac : observation.vendor
    }

    // MARK: - Identity

    private var identityCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "Client")
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading, spacing: DesignToken.Spacing.small
                ) {
                    detailRow("SSID", network?.displaySSID ?? "—")
                    detailRow("BSSID", bssid.isEmpty ? "—" : bssid)
                    detailRow("Vendor", observation.vendor.isEmpty ? "Unknown" : observation.vendor)
                    detailRow("Strongest RSSI", observation.rssi.map { "\($0) dBm" } ?? "—")
                    detailRow("Frames", "\(observation.frames)")
                    detailRow(
                        "Retries",
                        observation.frames > 0
                            ? "\(observation.retries) (\(Int((Double(observation.retries) / Double(observation.frames) * 100).rounded()))%)"
                            : "—")
                    detailRow("Airtime", "\(observation.airtimeMicroseconds / 1000) ms")
                    detailRow("Probes", observation.probes.isEmpty ? "—" : observation.probes.joined(separator: ", "))
                    detailRow("First seen", formatted(observation.firstSeen))
                    detailRow("Last seen", formatted(observation.lastSeen))
                    detailRow(
                        "Captured span",
                        spanLabel(observation.firstSeen, observation.lastSeen))
                }
            }
        }
    }

    // MARK: - Capabilities

    private var capabilitiesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    SectionLabel(text: "Capabilities")
                    Spacer()
                    if let capabilities = observation.capabilities {
                        StatusPill(
                            text: capabilities.generationLabel,
                            tone: capabilities.generation == .be || capabilities.generation == .ax
                                ? .good : .neutral)
                    }
                }
                if let capabilities = observation.capabilities, capabilities.hasCapabilities {
                    if !capabilities.summaryLine.isEmpty {
                        Text(capabilities.summaryLine)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading, spacing: DesignToken.Spacing.small
                    ) {
                        detailRow("PHY", capabilities.generationLabel)
                        detailRow(
                            "MIMO",
                            capabilities.streams.map { "\($0)×\($0)" } ?? "Not advertised")
                        detailRow("Basic rates", capabilities.ratesLabel ?? "—")
                        detailRow("802.11r FT", capabilities.fastTransition ? "Yes" : "—")
                        detailRow("PMF", capabilities.pmfCapable ? "Capable" : "—")
                        detailRow("Source", capabilities.source.label)
                    }
                    Text(capabilityFootnote(capabilities))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(
                        "No association frames for this client are in the capture. Capture the client joining its network to see what it advertises."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func capabilityFootnote(_ capabilities: ClientCapabilitySummary) -> String {
        switch capabilities.source {
        case .associationRequest, .reassociationRequest:
            return "Decoded from this client's own association request, so it is what the device advertised."
        case .beacon:
            return
                "The client's association request is not in the capture; these are the access point's advertised capabilities, not the client's."
        }
    }

    // MARK: - Locator

    private var locatorCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    SectionLabel(text: "Signal locator")
                    Spacer()
                    if canLocate {
                        AppButton(
                            isLocating ? "Stop" : "Start",
                            systemImage: isLocating ? "stop.fill" : "play.fill",
                            tone: .primary
                        ) {
                            toggleLocator()
                        }
                    }
                }
                if canLocate {
                    HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.large) {
                        Text(locator.state.smoothedRSSI.map { "\(Int($0.rounded()))" } ?? "—")
                            .font(.system(size: 54, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(locatorTint)
                        VStack(alignment: .leading, spacing: DesignToken.Spacing.hairline) {
                            Text(locator.state.proximity.label)
                                .font(.headline)
                                .foregroundColor(locatorTint)
                            if let trend = locator.state.trendLabel {
                                Text("\(trend) · \(locator.state.sampleCount) samples")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(locator.state.sampleCount) samples")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("dBm")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    sparkline
                    Text(locator.state.proximity.advice)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Ping when the signal gets stronger", isOn: $pingOnRise)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundColor(AppPalette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    Text("Tracking \(bssid).")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                    Text(
                        "Signal guidance, not direction finding. The reading follows the access point this client was seen on, because macOS only exposes per-client RSSI during a privileged monitor capture. Walls, bodies and antenna orientation change it unpredictably, so walk slowly and compare, never trust one step."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(
                        "This client has no BSSID yet. Capture longer so it associates, or start the locator from an access point row instead."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var locatorTint: Color {
        switch locator.state.proximity {
        case .strong: return AppPalette.ok
        case .good: return AppPalette.info
        case .fair: return AppPalette.warning
        case .far: return AppPalette.warning
        case .lost: return AppPalette.muted
        }
    }

    private var sparkline: some View {
        GeometryReader { geometry in
            Path { path in
                guard history.count > 1, geometry.size.width > 0 else { return }
                let lowest = history.min() ?? -100
                let highest = history.max() ?? -30
                let span = max(1, highest - lowest)
                for (index, value) in history.enumerated() {
                    let x =
                        geometry.size.width * CGFloat(index)
                        / CGFloat(history.count - 1)
                    let y =
                        geometry.size.height
                        * CGFloat(highest - value) / CGFloat(span)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                locatorTint,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(DesignToken.Surface.subtleFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(alignment: .topLeading) {
            if history.isEmpty {
                Text("Start to collect samples")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(DesignToken.Spacing.small)
            }
        }
    }

    // MARK: - Sampling

    private func toggleLocator() {
        isLocating.toggle()
        if isLocating {
            locator.reset()
            history = []
            statusMessage = nil
        }
    }

    @MainActor
    private func runLocator() async {
        guard isLocating, canLocate else { return }
        let scanner = WiFiScanner()
        while !Task.isCancelled, isLocating {
            let now = Date()
            do {
                let networks = try await scanner.scan()
                if let target = networks.first(where: {
                    $0.bssid.caseInsensitiveCompare(bssid) == .orderedSame
                }) {
                    let previous = locator.state.smoothedRSSI
                    locator.ingest(rssi: target.signal, at: now)
                    statusMessage = nil
                    history.append(target.signal)
                    if history.count > 90 {
                        history.removeFirst(history.count - 90)
                    }
                    if pingOnRise, let previous, let current = locator.state.smoothedRSSI,
                        current - previous >= 3
                    {
                        NSSound(named: NSSound.Name("Tink"))?.play()
                    }
                } else {
                    locator.tick(at: now)
                    statusMessage = "\(bssid) was not in the latest scan."
                }
            } catch {
                locator.tick(at: now)
                statusMessage = error.localizedDescription
            }
            // The sampler targets 4 Hz; a CoreWLAN scan takes what it takes, so
            // the average is fed at whatever cadence macOS returns.
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    // MARK: - Formatting

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.small) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(verbatim: value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date, date != .distantFuture, date != .distantPast else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }

    private func spanLabel(_ first: Date?, _ last: Date?) -> String {
        guard let first, let last, first != .distantFuture, first <= last else { return "—" }
        let seconds = Int(last.timeIntervalSince(first).rounded())
        if seconds < 60 { return "\(seconds) s" }
        return "\(seconds / 60) min \(seconds % 60) s"
    }
}
