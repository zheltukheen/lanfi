import Foundation

/// Builds a block-oriented protocol profile from a scan result. The analyzer is
/// deliberately independent of CoreWLAN and SwiftUI so every branch can be
/// unit tested with fixtures.
enum ProtocolAnalyzer {

    static func profile(for network: NetworkModel, metrics: NetworkMetrics?) -> ProtocolProfile {
        let radio = radioBlock(network)
        let eht = ehtBlock(network)
        let security = securityBlock(network)
        let mobility = mobilityBlock(network)
        let spectrum = spectrumBlock(network, metrics: metrics)
        let format = formatBlock(network)
        let vendor = vendorBlock(network)

        let blocks = [radio, eht, security, spectrum, mobility, format, vendor]
        let warnings = blocks.flatMap { block in
            block.facts
                .filter { $0.status == .critical || $0.status == .warning }
                .map { "\(block.title): \($0.label) — \($0.value)" }
        }

        return ProtocolProfile(
            networkId: network.id,
            title: network.displaySSID,
            subtitle: network.bssid.isEmpty ? "No BSSID" : network.bssid,
            formatLine: [
                network.band.label,
                network.generation.label,
                network.channelWidthLabel == "-" ? nil : "\(network.channelWidthLabel) MHz",
                network.security,
            ].compactMap { $0 }.joined(separator: " · "),
            band: network.band,
            blocks: blocks,
            warnings: warnings
        )
    }

    static func coverage(for networks: [NetworkModel]) -> ProtocolCoverage {
        guard !networks.isEmpty else { return .empty }

        var bandCounts: [String: Int] = [:]
        var generationCounts: [String: Int] = [:]
        var securityCounts: [String: Int] = [:]
        var sixGHz = 0
        var wiFi7 = 0
        var pmf = 0
        var wps = 0
        var fastTransition = 0
        var open = 0
        var critical = 0

        for network in networks {
            bandCounts[network.band.label, default: 0] += 1
            generationCounts[network.generation.label, default: 0] += 1
            securityCounts[network.security, default: 0] += 1

            if network.band == .band6 { sixGHz += 1 }
            if network.generation == .mode11be { wiFi7 += 1 }
            if network.pmfRequired == true { pmf += 1 }
            if network.wpsEnabled == true { wps += 1 }
            if network.fastTransition == true { fastTransition += 1 }
            if network.security.lowercased().contains("open") { open += 1 }

            let metrics = NetworkAnalyzer.metricsFor(network, among: networks)
            if metrics.securityScore < 40 || metrics.qualityScore < 30 { critical += 1 }
        }

        return ProtocolCoverage(
            networkCount: networks.count,
            bandCounts: bandCounts,
            generationCounts: generationCounts,
            securityCounts: securityCounts,
            sixGHzCount: sixGHz,
            wiFi7Count: wiFi7,
            pmfCount: pmf,
            wpsCount: wps,
            fastTransitionCount: fastTransition,
            openCount: open,
            criticalCount: critical
        )
    }

    // MARK: - Blocks

    private static func radioBlock(_ network: NetworkModel) -> ProtocolBlock {
        var facts: [ProtocolFact] = [
            ProtocolFact(
                id: "generation",
                label: "PHY generation",
                value: network.generation.label,
                detail: generationDetail(network.generation),
                status: network.generation == .unknown ? .unknown : .good
            ),
            ProtocolFact(
                id: "band",
                label: "Band",
                value: network.band.label,
                detail: network.isDFSChannel ? "DFS channel — CAC may be required" : nil,
                status: network.band == .unknown ? .unknown : .info
            ),
            ProtocolFact(
                id: "channel",
                label: "Channel / width",
                value: "\(network.channel) · \(network.channelWidthLabel) MHz",
                detail: network.centerFrequency.map { "Center \($0) MHz" },
                status: network.channel > 0 ? .info : .unknown
            ),
            ProtocolFact(
                id: "rate",
                label: "Estimated PHY rate",
                value: network.maxRateLabel == "-" ? "Not advertised" : "\(network.maxRateLabel) Mbps",
                detail: network.ratesEstimated ? "Estimated from PHY and width" : nil,
                status: network.maxRate == nil ? .unknown : .info
            ),
            ProtocolFact(
                id: "streams",
                label: "Spatial streams",
                value: network.streams.map(String.init) ?? "Not advertised",
                detail: network.streams == nil ? "Requires HT/VHT/HE capabilities IE" : nil,
                status: network.streams == nil ? .unknown : .good
            ),
        ]

        if let country = network.countryCode {
            facts.append(ProtocolFact(id: "country", label: "Regulatory domain", value: country))
        }

        let features = detectedFeatures(network)
        if !features.isEmpty {
            facts.append(
                ProtocolFact(
                    id: "features",
                    label: "Detected capabilities",
                    value: features.joined(separator: ", "),
                    status: .good
                )
            )
        }

        return ProtocolBlock(
            id: "radio",
            title: "Radio & PHY",
            subtitle: "802.11 generation, band and channel plan",
            systemImage: "antenna.radiowaves.left.and.right",
            facts: facts,
            status: network.channel > 0 ? .good : .unknown
        )
    }

    private static func ehtBlock(_ network: NetworkModel) -> ProtocolBlock {
        let ehtElements = network.informationElements.filter { element in
            let name = element.name.lowercased()
            return name.contains("eht") || name.contains("multi-link") || name.contains("mlo")
                || name.contains("320")
        }
        let isWiFi7 = network.generation == .mode11be
        let hasEHT = isWiFi7 || !ehtElements.isEmpty
        let mloElement = ehtElements.contains { $0.name.lowercased().contains("multi-link") }
        let ehtOperation = ehtElements.first { $0.name.localizedCaseInsensitiveContains("EHT Operation") }
        let reports320 =
            network.channelWidthMHz >= 320
            || (ehtOperation?.summary.localizedCaseInsensitiveContains("320 MHz") ?? false)
        let puncturing = EHTPuncturing.parse(elements: network.informationElements)
        let puncturingValue: String
        let puncturingDetail: String
        let puncturingStatus: ProtocolFactStatus
        if let puncturing, puncturing.bitmapPresent {
            if puncturing.puncturedSubchannels.isEmpty {
                puncturingValue = "None"
                puncturingDetail = "Disabled subchannel bitmap present, no subchannels punctured"
                puncturingStatus = .good
            } else {
                puncturingValue = puncturing.puncturedSubchannels.map(String.init).joined(separator: ", ")
                puncturingDetail =
                    "Punctured 20 MHz subchannels (from lowest frequency, of "
                    + "\(puncturing.validSubchannelCount)); AP avoids them due to interference"
                puncturingStatus = .info
            }
        } else {
            puncturingValue = "Not reported"
            puncturingDetail = "EHT Operation carries no disabled subchannel bitmap"
            puncturingStatus = .unknown
        }
        var facts: [ProtocolFact] = [
            ProtocolFact(
                id: "wifi7",
                label: "Wi-Fi 7 / EHT",
                value: hasEHT ? "Advertised" : "Not advertised",
                detail: isWiFi7 ? "11be PHY reported by CoreWLAN" : nil,
                status: hasEHT ? .good : .unknown
            ),
            ProtocolFact(
                id: "eht-ie",
                label: "EHT information elements",
                value: ehtElements.isEmpty ? "None decoded" : "\(ehtElements.count) decoded",
                detail: ehtElements.map(\.name).prefix(3).joined(separator: ", "),
                status: ehtElements.isEmpty ? .unknown : .info
            ),
            ProtocolFact(
                id: "mlo",
                label: "Multi-link operation",
                value: mloElement ? "ML IE decoded" : "Not exposed by CoreWLAN",
                detail: mloElement
                    ? "Multi-Link element present; open a monitor capture in Offline packet analysis for the full link set (MLO groups)"
                    : "macOS scan APIs do not report MLO link sets; capture beacons in monitor mode and open them in Offline packet analysis",
                status: mloElement ? .info : .unknown
            ),
            ProtocolFact(
                id: "width320",
                label: "320 MHz",
                value: reports320 ? "Reported" : "Not reported",
                detail: reports320
                    ? "EHT Operation or CoreWLAN reports 320 MHz"
                    : "CoreWLAN width: \(network.channelWidthLabel) MHz",
                status: reports320 ? .good : .unknown
            ),
            ProtocolFact(
                id: "puncturing",
                label: "Preamble puncturing",
                value: puncturingValue,
                detail: puncturingDetail,
                status: puncturingStatus
            ),
        ]
        if network.band == .band6 {
            facts.append(
                ProtocolFact(
                    id: "six",
                    label: "6 GHz operation",
                    value: "Yes",
                    detail: "Preferred scanning channels and AFC may apply",
                    status: .good
                )
            )
        }
        return ProtocolBlock(
            id: "eht",
            title: "Wi-Fi 7 & MLO",
            subtitle: "EHT capabilities, 320 MHz and multi-link visibility",
            systemImage: "wifi.router",
            facts: facts,
            status: hasEHT ? .good : .unknown
        )
    }

    private static func securityBlock(_ network: NetworkModel) -> ProtocolBlock {
        let security = network.security.lowercased()
        let isOpen = security.contains("open")
        let isWEP = security.contains("wep")
        let isLegacyWPA = security.contains("wpa ") || security == "wpa"

        let securityStatus: ProtocolFactStatus =
            isOpen || isWEP ? .critical : (isLegacyWPA || network.wpsEnabled == true ? .warning : .good)

        var facts: [ProtocolFact] = [
            ProtocolFact(
                id: "mode",
                label: "Security mode",
                value: network.security,
                detail: isOpen ? "Traffic is unencrypted" : nil,
                status: securityStatus
            ),
            ProtocolFact(
                id: "pmf",
                label: "Management frame protection",
                value: pmfLabel(network.pmfRequired),
                detail: network.pmfRequired == true
                    ? "802.11w required — robust management frames"
                    : "PMF is optional or not advertised",
                status: network.pmfRequired == true ? .good : .info
            ),
            ProtocolFact(
                id: "wps",
                label: "Wi-Fi Protected Setup",
                value: network.wpsEnabled == true
                    ? "Enabled" : (network.wps == "Unknown" ? "Not advertised" : "Disabled"),
                detail: network.wpsEnabled == true ? "WPS may allow brute-force attacks" : nil,
                status: network.wpsEnabled == true ? .warning : .good
            ),
            ProtocolFact(
                id: "fast-transition",
                label: "Fast transition (802.11r)",
                value: network.fastTransition == true ? "Supported" : "Not advertised",
                status: network.fastTransition == true ? .good : .info
            ),
            ProtocolFact(
                id: "enterprise",
                label: "Authentication",
                value: security.contains("enterprise")
                    ? "802.1X / Enterprise" : (security.contains("personal") ? "Personal PSK" : "Open / other"),
                status: .info
            ),
        ]

        if network.wpsEnabled == true, let wps = network.wps, !wps.isEmpty {
            facts.append(ProtocolFact(id: "wps-detail", label: "WPS details", value: wps, status: .warning))
        }

        return ProtocolBlock(
            id: "security",
            title: "Security & trust",
            subtitle: "WPA mode, PMF, WPS and authentication",
            systemImage: "lock.shield",
            facts: facts,
            status: securityStatus
        )
    }

    private static func mobilityBlock(_ network: NetworkModel) -> ProtocolBlock {
        let hasRM = hasElement(network, nameContains: "RM Enabled")
        let hasBSS = hasSummary(network, contains: "BSS Transition")
        let hasFT = network.fastTransition == true

        var facts: [ProtocolFact] = [
            ProtocolFact(
                id: "ft",
                label: "802.11r Fast BSS Transition",
                value: hasFT ? "Supported" : "Not advertised",
                detail: "Speeds up roaming between access points",
                status: hasFT ? .good : .info
            ),
            ProtocolFact(
                id: "rm",
                label: "802.11k Radio Measurement",
                value: hasRM ? "Supported" : "Not advertised",
                detail: hasRM ? "Neighbor reports help clients choose APs" : nil,
                status: hasRM ? .good : .info
            ),
            ProtocolFact(
                id: "bss",
                label: "802.11v BSS Transition",
                value: hasBSS ? "Supported" : "Not advertised",
                detail: hasBSS ? "Network can steer clients between BSSIDs" : nil,
                status: hasBSS ? .good : .info
            ),
            ProtocolFact(
                id: "pmf-roam",
                label: "Protected roaming",
                value: network.pmfRequired == true ? "PMF required" : "PMF optional",
                status: network.pmfRequired == true ? .good : .info
            ),
        ]

        if hasSummary(network, contains: "TWT Responder") {
            facts.append(ProtocolFact(id: "twt", label: "Target Wake Time", value: "Supported", status: .good))
        }

        let status: ProtocolFactStatus = (hasFT || hasRM || hasBSS) ? .good : .info
        return ProtocolBlock(
            id: "mobility",
            title: "Roaming & mobility",
            subtitle: "802.11r / k / v and client steering",
            systemImage: "arrow.triangle.swap",
            facts: facts,
            status: status
        )
    }

    private static func spectrumBlock(_ network: NetworkModel, metrics: NetworkMetrics?) -> ProtocolBlock {
        let utilization = network.channelUtilization.map { "\($0)%" } ?? "Not advertised"
        let congestion = metrics?.congestionScore
        let overlap = metrics?.overlappingCount
        let snr = network.snr.map { "\($0) dB" } ?? "Not available"

        let status: ProtocolFactStatus
        if let congestion, congestion < 40 {
            status = .critical
        } else if let congestion, congestion < 65 {
            status = .warning
        } else {
            status = .good
        }

        let facts: [ProtocolFact] = [
            ProtocolFact(
                id: "rssi",
                label: "Signal / noise",
                value: "\(network.signal) dBm / \(network.noiseLabel) dBm",
                status: network.signal > -75 ? .good : .warning
            ),
            ProtocolFact(
                id: "snr", label: "SNR", value: snr, status: network.snr.map { $0 >= 25 ? .good : .warning } ?? .unknown
            ),
            ProtocolFact(
                id: "utilization",
                label: "Channel utilization",
                value: utilization,
                status: network.channelUtilization.map { $0 > 60 ? .warning : .good } ?? .unknown
            ),
            ProtocolFact(
                id: "congestion",
                label: "Congestion score",
                value: congestion.map(String.init) ?? "Not analyzed",
                detail: overlap.map { "\($0) overlapping APs" },
                status: status
            ),
            ProtocolFact(
                id: "overlap",
                label: "Co-channel / overlap",
                value: metrics.map { "\($0.coChannelCount) / \($0.overlappingCount)" } ?? "—",
                status: status
            ),
        ]

        return ProtocolBlock(
            id: "spectrum",
            title: "Spectrum & airtime",
            subtitle: "Signal quality, utilization and interference",
            systemImage: "waveform.path.ecg",
            facts: facts,
            status: status
        )
    }

    private static func formatBlock(_ network: NetworkModel) -> ProtocolBlock {
        var facts: [ProtocolFact] = [
            ProtocolFact(
                id: "format",
                label: "Network format",
                value: network.mode,
                detail: network.mode == "IBSS" ? "Peer-to-peer / ad-hoc network" : "Access-point infrastructure",
                status: .info
            ),
            ProtocolFact(
                id: "hidden",
                label: "SSID visibility",
                value: network.ssid.isEmpty ? "Hidden" : "Broadcast",
                detail: network.ssid.isEmpty ? "Hidden SSIDs are not a security control" : nil,
                status: network.ssid.isEmpty ? .warning : .good
            ),
            ProtocolFact(
                id: "bssid",
                label: "BSSID",
                value: network.bssid.isEmpty ? "Unavailable" : network.bssid,
                detail: network.bssid.isEmpty ? "Location permission may be required" : nil,
                status: network.bssid.isEmpty ? .warning : .info
            ),
            ProtocolFact(
                id: "type",
                label: "Reported type",
                value: network.type ?? network.mode,
                status: .info
            ),
            ProtocolFact(
                id: "clients",
                label: "Associated stations",
                value: network.clients.map(String.init) ?? network.stations.map(String.init) ?? "Not advertised",
                detail: "From BSS Load when the AP exposes it",
                status: .info
            ),
        ]

        if let code = network.countryCode {
            facts.append(ProtocolFact(id: "country-format", label: "Country", value: code))
        }

        return ProtocolBlock(
            id: "format",
            title: "Network format",
            subtitle: "Infrastructure, hidden, IBSS and client load",
            systemImage: "network",
            facts: facts,
            status: .info
        )
    }

    private static func vendorBlock(_ network: NetworkModel) -> ProtocolBlock {
        let vendorIEs = network.informationElements.filter { $0.name.contains("Vendor Specific") }
        let ieNames = network.informationElements.map(\.name)
        let hasHT = ieNames.contains { $0.contains("HT Capabilities") }
        let hasVHT = ieNames.contains { $0.contains("VHT Capabilities") }
        let hasHE = ieNames.contains { $0.contains("HE Capabilities") }
        let hasWMM = network.informationElements.contains { $0.summary.contains("WMM") }

        var features: [String] = []
        if hasHT { features.append("HT") }
        if hasVHT { features.append("VHT") }
        if hasHE { features.append("HE") }
        if hasWMM { features.append("WMM") }

        let facts: [ProtocolFact] = [
            ProtocolFact(
                id: "vendor", label: "Vendor", value: network.vendor, status: network.vendor == "-" ? .unknown : .info),
            ProtocolFact(
                id: "ies",
                label: "Information elements",
                value:
                    "\(network.ieCount ?? network.informationElements.count) IEs · \(network.ieTotalLength ?? 0) bytes",
                status: .info
            ),
            ProtocolFact(
                id: "capabilities",
                label: "Capability IEs",
                value: features.isEmpty ? "None decoded" : features.joined(separator: ", "),
                status: features.isEmpty ? .unknown : .good
            ),
            ProtocolFact(
                id: "vendor-ies",
                label: "Vendor elements",
                value: vendorIEs.isEmpty ? "None" : "\(vendorIEs.count) decoded",
                detail: vendorIEs.prefix(2).map(\.name).joined(separator: ", "),
                status: .info
            ),
        ]

        return ProtocolBlock(
            id: "vendor",
            title: "Vendor & capabilities",
            subtitle: "OUI, HT/VHT/HE and vendor information elements",
            systemImage: "cpu",
            facts: facts,
            status: .info
        )
    }

    // MARK: - Helpers

    private static func pmfLabel(_ required: Bool?) -> String {
        switch required {
        case true?: return "Required"
        case false?: return "Not required"
        case nil: return "Not advertised"
        }
    }

    private static func generationDetail(_ generation: WiFiStandard) -> String {
        switch generation {
        case .mode11be: return "Wi-Fi 7 — EHT, 6 GHz, MLO capable"
        case .mode11ax: return "Wi-Fi 6/6E — HE, OFDMA, 6 GHz"
        case .mode11ac: return "Wi-Fi 5 — VHT, 5 GHz"
        case .mode11n: return "Wi-Fi 4 — HT, 2.4/5 GHz"
        case .mode11a: return "Legacy 5 GHz OFDM"
        case .mode11b: return "Legacy 2.4 GHz DSSS"
        case .mode11g: return "Legacy 2.4 GHz OFDM"
        case .unknown: return "PHY mode not advertised"
        }
    }

    private static func detectedFeatures(_ network: NetworkModel) -> [String] {
        var features: [String] = []
        if network.isDFSChannel { features.append("DFS") }
        if network.wideChannelLabel == "Yes" { features.append("wide channel") }
        if network.streams != nil { features.append("MIMO") }
        if network.informationElements.contains(where: { $0.name.contains("HE Capabilities") }) {
            features.append("HE")
        }
        if network.informationElements.contains(where: { $0.name.contains("VHT Capabilities") }) {
            features.append("VHT")
        }
        return features
    }

    private static func hasElement(_ network: NetworkModel, nameContains text: String) -> Bool {
        network.informationElements.contains { $0.name.localizedCaseInsensitiveContains(text) }
    }

    private static func hasSummary(_ network: NetworkModel, contains text: String) -> Bool {
        network.informationElements.contains { $0.summary.localizedCaseInsensitiveContains(text) }
    }
}
