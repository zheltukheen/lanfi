import Foundation

enum DecodedFieldGroup: String, CaseIterable, Identifiable {
    case radio
    case capabilities
    case security
    case sixGHz
    case mlo
    case informationElements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radio: return String(localized: "Radio")
        case .capabilities: return String(localized: "Capabilities")
        case .security: return String(localized: "Security")
        case .sixGHz: return String(localized: "6 GHz")
        case .mlo: return String(localized: "Multi-Link")
        case .informationElements: return String(localized: "Information elements")
        }
    }
}

/// One decoded value that can become a table column, a CSV cell or a report
/// row. Keys are stable strings: `radio.frequency`, `mlo.apmld`,
/// `ie.element.255.0`. A field exists only when the value exists, so a column
/// shows a dash instead of inventing data.
struct DecodedField: Identifiable, Equatable {
    let key: String
    let label: String
    let group: DecodedFieldGroup
    let value: String

    var id: String { key }
}

enum DecodedFieldCatalog {
    static func fields(for network: NetworkModel) -> [DecodedField] {
        var fields: [DecodedField] = []

        func add(_ group: DecodedFieldGroup, _ key: String, _ label: String, _ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "-" else { return }
            fields.append(DecodedField(key: key, label: label, group: group, value: trimmed))
        }

        // Radio
        add(.radio, "radio.frequency", String(localized: "Frequency"), network.frequencyMHz.map { "\($0) MHz" })
        add(
            .radio, "radio.centerfrequency", String(localized: "Center frequency"),
            network.centerFrequency.map { "\($0) MHz" })
        add(
            .radio, "radio.dfs", String(localized: "DFS channel"),
            network.isDFSChannel ? yesNo(network.isDFSChannel) : nil)
        if network.band == .band6 {
            add(
                .radio, "radio.psc", String(localized: "Preferred scanning channel"),
                yesNo(network.isPreferredScanningChannel))
        }
        add(
            .radio, "radio.utilization", String(localized: "Channel utilization"),
            network.channelUtilization.map { "\($0)%" })
        add(
            .radio, "radio.beaconinterval", String(localized: "Beacon interval"),
            network.beaconInterval.map { "\($0) ms" })
        add(
            .radio, "radio.beaconrate", String(localized: "Beacon rate"),
            network.beaconRate.map { String(format: "%.1f Mbit/s", $0) })
        add(
            .radio, "radio.beaconairtime", String(localized: "Beacon airtime"),
            network.beaconAirtime.map { String(format: "%.1f ms/s", $0) })
        add(
            .radio, "radio.puncturing", String(localized: "Puncturing"),
            EHTPuncturing.parse(elements: network.informationElements)?.columnLabel)
        add(.radio, "radio.country", String(localized: "Country"), network.countryCode)

        // Capabilities
        add(
            .capabilities, "cap.maxrate", String(localized: "Max rate"),
            network.maxRate.map { String(format: "%.0f Mbit/s", $0) })
        add(
            .capabilities, "cap.minrate", String(localized: "Min rate"),
            network.minRate.map { String(format: "%.0f Mbit/s", $0) })
        add(
            .capabilities, "cap.maxbasicrate", String(localized: "Max basic rate"),
            network.maxBasicRate.map { String(format: "%.0f Mbit/s", $0) })
        add(
            .capabilities, "cap.minbasicrate", String(localized: "Min basic rate"),
            network.minBasicRate.map { String(format: "%.0f Mbit/s", $0) })
        add(.capabilities, "cap.basicrates", String(localized: "Basic rates"), network.basicRatesLabel)
        add(.capabilities, "cap.streams", String(localized: "Spatial streams"), network.streams.map(String.init))
        add(.capabilities, "cap.clients", String(localized: "Clients"), network.clients.map(String.init))
        add(.capabilities, "cap.stations", String(localized: "Stations"), network.stations.map(String.init))
        add(.capabilities, "cap.type", String(localized: "Type"), network.type)
        add(.capabilities, "cap.protection", String(localized: "Protection mode"), network.protectionMode)
        add(.capabilities, "cap.wpsmodel", String(localized: "WPS model"), network.routerModel)
        add(
            .capabilities, "cap.ratesestimated", String(localized: "Rates estimated"),
            network.ratesEstimated ? String(localized: "Yes") : nil)

        // Security
        add(
            .security, "security.fasttransition", String(localized: "Fast transition"),
            network.fastTransition.map { yesNo($0) })
        add(
            .security, "security.pmf", String(localized: "PMF required"),
            network.pmfRequired.map { yesNo($0) })
        add(
            .security, "security.wpsenabled", String(localized: "WPS enabled"),
            network.wpsEnabled.map { yesNo($0) })
        add(.security, "security.wps", String(localized: "WPS state"), network.wps)

        // 6 GHz operation
        if let info = sixGHzInfo(for: network) {
            add(.sixGHz, "sixghz.powermode", String(localized: "Power mode"), info.powerMode.title)
            add(
                .sixGHz, "sixghz.width", String(localized: "6 GHz width"),
                "\(info.widthMHz) MHz")
            add(
                .sixGHz, "sixghz.duplicatebeacon", String(localized: "Duplicate beacon"),
                yesNo(info.duplicateBeacon))
            add(
                .sixGHz, "sixghz.minimumrate", String(localized: "6 GHz minimum rate"),
                "\(info.minimumRate)")
        }

        // Multi-Link
        if let mlo = MLOInfo.parse(elements: network.informationElements, widthMHz: network.channelWidthMHz) {
            add(.mlo, "mlo.apmld", String(localized: "AP MLD address"), mlo.apMLD)
            add(
                .mlo, "mlo.links", String(localized: "Links"),
                mlo.links.map { link in
                    link.bssid.map { "\(link.linkID): \($0)" } ?? "\(link.linkID)"
                }.joined(separator: ", "))
            add(.mlo, "mlo.320mhz", String(localized: "320 MHz"), yesNo(mlo.is320MHz))
        }

        // Information elements, one key per element occurrence so vendor IEs are
        // addressable without hard-coding every vendor.
        add(.informationElements, "ie.count", String(localized: "IE count"), network.ieCount.map(String.init))
        add(
            .informationElements, "ie.totallength", String(localized: "IE total length"),
            network.ieTotalLength.map { "\($0) B" })
        let countryChannels = network.countryIEChannels
        add(
            .informationElements, "ie.countrychannels", String(localized: "Country IE channels"),
            countryChannels.isEmpty ? nil : countryChannels.map(String.init).joined(separator: ", "))
        var occurrences: [Int: Int] = [:]
        for element in network.informationElements {
            let occurrence = occurrences[element.elementId, default: 0]
            occurrences[element.elementId] = occurrence + 1
            add(
                .informationElements, "ie.element.\(element.elementId).\(occurrence)",
                element.name, element.summary)
        }

        return fields
    }

    /// The value of one catalogue key, or nil when this network does not carry
    /// it. Used by table cells and CSV export so both agree.
    static func value(for key: String, network: NetworkModel) -> String? {
        fields(for: network).first { $0.key == key }?.value
    }

    /// Union of keys across networks, for an "all fields" CSV header. Sorted so
    /// the same scan always produces the same column order.
    static func allKeys(in networks: [NetworkModel]) -> [String] {
        Array(Set(networks.flatMap { fields(for: $0).map(\.key) })).sorted()
    }

    private static func sixGHzInfo(for network: NetworkModel) -> SixGHzOperationInfo? {
        for element in network.informationElements
        where element.name.localizedCaseInsensitiveContains("HE Operation")
            || element.name.localizedCaseInsensitiveContains("6 GHz")
        {
            if let info = SixGHzOperationInfo.parse(elementRawHex: element.rawHex) {
                return info
            }
        }
        return nil
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }
}

/// CSV with one column per decoded field. The header is the union of keys in
/// the scan, so two rows with different information elements stay aligned.
struct DecodedFieldCSVExporter {
    func make(networks: [NetworkModel]) -> String {
        let keys = DecodedFieldCatalog.allKeys(in: networks)
        let headers = keys.map { "\"\($0)\"" }.joined(separator: ",")
        let rows = networks.map { network in
            let fields = Dictionary(
                uniqueKeysWithValues: DecodedFieldCatalog.fields(for: network).map { ($0.key, $0.value) })
            return keys.map { key in
                let value = fields[key] ?? ""
                return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ",")
        }
        return "\u{FEFF}" + ([headers] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
