import Foundation

extension DiagnosticsReport {
    /// Plain-language attribution for the Internet Check card.
    ///
    /// Order matters: a broken local link or address explains everything above
    /// it, so it wins over a failed gateway or DNS query.
    var verdict: DiagnosticVerdict {
        let link = check("wifi-link")
        let address = check("ipv4")
        let signal = check("wifi-signal")
        let gateway = check("gateway")
        let dns = check("dns")
        let internet = check("internet")
        let latency = check("latency")

        if link?.status == .fail || address?.status == .fail { return .localNetwork }
        if signal?.status == .fail { return .localNetwork }
        if gateway?.status == .fail { return .router }
        if latency?.status == .fail { return .provider }
        if dns?.status == .fail { return .dns }
        if internet?.status == .fail { return .web }
        return .healthy
    }

    /// The checks that support the verdict, in report order.
    var verdictEvidence: [DiagnosticCheck] {
        let ids: Set<String>
        switch verdict {
        case .localNetwork:
            ids = ["wifi-interface", "wifi-link", "wifi-signal", "ipv4"]
        case .router:
            ids = ["gateway"]
        case .provider:
            ids = ["gateway", "latency"]
        case .dns:
            ids = ["dns", "dns-servers"]
        case .web:
            ids = ["internet"]
        case .healthy:
            ids = ["wifi-link", "gateway", "dns", "internet"]
        }
        return checks.filter { ids.contains($0.id) }
    }

    private func check(_ id: String) -> DiagnosticCheck? {
        checks.first { $0.id == id }
    }
}
