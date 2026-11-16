import Foundation

/// Why a nearby network may be hard to see in the table. Deliberately plain
/// language: the gap review found that buyers could not tell what a channel
/// number, PSC or DFS means.
struct VisibilityAdvice: Equatable, Identifiable {
    enum Kind: String {
        case preferredScanning
        case notPreferredScanning
        case dfs
        case hiddenSSID
    }

    let kind: Kind
    let title: String
    let detail: String

    var id: String { kind.rawValue }
}

enum VisibilityAdvisor {
    /// Ordered by how much each fact affects discovery.
    static func advice(for network: NetworkModel) -> [VisibilityAdvice] {
        var items: [VisibilityAdvice] = []

        if network.band == .band6 {
            if network.isPreferredScanningChannel {
                items.append(
                    VisibilityAdvice(
                        kind: .preferredScanning,
                        title: String(localized: "Preferred scanning channel"),
                        detail: String(
                            localized:
                                "6 GHz channel \(network.channel) is a PSC channel. Active scans probe it first, so this access point is found quickly."
                        )))
            } else {
                items.append(
                    VisibilityAdvice(
                        kind: .notPreferredScanning,
                        title: String(localized: "Not a preferred scanning channel"),
                        detail: String(
                            localized:
                                "6 GHz channel \(network.channel) is not a PSC channel. macOS active scans probe PSC channels first, so this access point can appear late or not at all; a passive scan is needed to see it reliably."
                        )))
            }
        }

        if network.band == .band5 && network.isDFSChannel {
            items.append(
                VisibilityAdvice(
                    kind: .dfs,
                    title: String(localized: "DFS channel"),
                    detail: String(
                        localized:
                            "5 GHz channel \(network.channel) is shared with radar. The access point must stay quiet during a radar check, so it can disappear for a minute or more."
                    )))
        }

        if network.ssid.isEmpty {
            items.append(
                VisibilityAdvice(
                    kind: .hiddenSSID,
                    title: String(localized: "Hidden network name"),
                    detail: String(
                        localized:
                            "This access point does not broadcast an SSID. Scans still report its BSSID, channel and security."
                    )))
        }

        return items
    }

    /// Shown in the empty workspace: the question the gap review says buyers
    /// ask first ("my 6 GHz network is missing").
    static var emptyScanHint: String {
        String(
            localized:
                "Missing a 6 GHz network? macOS active scans probe only the preferred scanning channels (PSC). An access point on another 6 GHz channel is found by passive scanning, which LanFi does not do yet."
        )
    }
}
