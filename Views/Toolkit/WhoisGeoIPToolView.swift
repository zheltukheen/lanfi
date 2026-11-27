import SwiftUI

/// One screen for Whois and GeoIP: one target field, both answers on one page.
///
/// Both tools take the same input (a domain, host or address) and are usually
/// consulted together — "who owns this name and where does it live" — so they
/// share one page instead of a tab strip that hid half the answer. The query is
/// mirrored between the models, so a lookup runs against the same target.
struct WhoisGeoIPToolView: View {
    @ObservedObject var whois: WhoisToolModel
    @ObservedObject var geo: GeoIPToolModel
    @ObservedObject var toolkit: ToolkitViewModel
    /// GeoIP used to fill itself with this Mac's address on appear, which put
    /// the local connection under every Whois answer. The page now stays empty
    /// until a search, and "My IP" is an explicit mode that hides the
    /// registration instead of stacking under it.
    @State private var showsMyIP = false

    private var isRunning: Bool { whois.isRunning || geo.isRunning }

    private var hasGeoContent: Bool {
        geo.isRunning || geo.report != nil || geo.errorMessage != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolkitHeaderBar {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Whois & GeoIP")
                        .font(.headline)
                    Text("Registration and location for one target, on one page.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } trailing: {
                if isRunning {
                    ProgressView().controlSize(.small)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                    targetCard
                    if showsMyIP {
                        if hasGeoContent {
                            GeoIPToolView(model: geo, showsControls: false)
                        }
                    } else {
                        WhoisToolView(model: whois, showsControls: false)
                        if hasGeoContent {
                            Divider()
                            GeoIPToolView(model: geo, showsControls: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appContentPadding()
            }
        }
        .onAppear { autoRunForDeepLink() }
        .onChange(of: toolkit.selection) { _ in autoRunForDeepLink() }
        .onChange(of: whois.query) { value in
            if !value.isEmpty, geo.query != value { geo.query = value }
        }
        .onChange(of: geo.query) { value in
            if !value.isEmpty, whois.query != value { whois.query = value }
        }
    }

    private var targetCard: some View {
        ToolkitCard {
            HStack(spacing: DesignToken.Spacing.small) {
                ToolTargetField(
                    text: $whois.query, placeholder: "Domain, host or IP address",
                    onSubmit: runBoth
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: DesignToken.Layout.controlWidthLarge)
                .onSubmit(runBoth)
                AppButton("Look Up", tone: .primary) { runBoth() }
                    .disabled(isRunning)
                AppButton("My IP", systemImage: "location") {
                    showsMyIP = true
                    geo.query = ""
                    geo.run(myIP: true)
                }
                .disabled(isRunning)
                AppButton("Clear", tone: .quiet) {
                    showsMyIP = false
                    whois.clear()
                    geo.clear()
                }
                .disabled(isRunning)
                Spacer()
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if isRunning { return String(localized: "Looking up…") }
        let target =
            showsMyIP
            ? (geo.report?.ip ?? "")
            : (whois.report?.name ?? geo.report?.ip ?? whois.query)
        return target.isEmpty ? String(localized: "Ready") : target
    }

    private var statusTone: ToolkitTone {
        if isRunning { return .running }
        return whois.report == nil && geo.report == nil ? .neutral : .good
    }

    private func runBoth() {
        showsMyIP = false
        geo.query = whois.query
        whois.run()
        geo.run()
    }

    /// A deep link to either tool should show its answer without a second
    /// click; the merged page never hides one behind a tab.
    private func autoRunForDeepLink() {
        switch toolkit.selection {
        case .geoIP:
            // No implicit "My IP": a deep link may carry a target in the
            // mirrored query, and the page otherwise stays empty.
            if geo.report == nil, !geo.isRunning, !geo.query.isEmpty { geo.run() }
        case .whois:
            if whois.report == nil, !whois.isRunning, !whois.query.isEmpty { whois.run() }
        default:
            break
        }
    }
}
