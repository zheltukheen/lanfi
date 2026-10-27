import Foundation
import CoreWLAN

enum WiFiError: LocalizedError {
    case interfaceNotFound
    case wifiPoweredOff
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .interfaceNotFound:
            return "Wi-Fi interface not found"
        case .wifiPoweredOff:
            return "Wi-Fi is off"
        case .scanFailed(let message):
            return message.isEmpty ? "Wi-Fi scan failed" : message
        }
    }
}

actor WiFiScanner {
    func scan() async throws -> [NetworkModel] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let networks = try Self.performScan()
                    continuation.resume(returning: networks)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func performScan() throws -> [NetworkModel] {
        let client = CWWiFiClient.shared()
        let preferred = UserDefaults.standard.string(forKey: "LanFi.wifiInterface")
        let interface = preferred.flatMap { client.interface(withName: $0) } ?? client.interface()
        guard let interface else {
            throw WiFiError.interfaceNotFound
        }
        guard interface.powerOn() else {
            throw WiFiError.wifiPoweredOff
        }

        let results: Set<CWNetwork>
        do {
            results = try interface.scanForNetworks(withName: nil, includeHidden: true)
        } catch {
            throw WiFiError.scanFailed(error.localizedDescription)
        }

        return results.map { makeModel(from: $0) }
    }

    private static func makeModel(from network: CWNetwork) -> NetworkModel {
        let ssid = network.ssid ?? ""
        let bssid = (network.bssid ?? "").uppercased()
        let channelNumber = network.wlanChannel?.channelNumber ?? 0
        let band = mapBand(network.wlanChannel?.channelBand)
        let channelWidthMHz = mapChannelWidth(network.wlanChannel?.channelWidth)
        let generation = mapGeneration(network)
        let security = securityDescription(for: network)
        let vendor = bssid.isEmpty ? "-" : OUIParser.vendor(for: bssid)
        let mode = network.ibss ? "IBSS" : "Infrastructure"

        let noiseValue = Int(network.noiseMeasurement)
        let noise = noiseValue == 0 ? nil : noiseValue
        let rssi = Int(network.rssiValue)
        let snr = noise.map { rssi - $0 }
        let beaconInterval = network.beaconInterval == 0 ? nil : Int(network.beaconInterval)
        let countryCode = network.countryCode
        let ieData = network.informationElementData
        let ieTotalLength = ieData?.count
        let centerFrequency = centerFrequency(channel: channelNumber, band: band)
        let rateEstimate = estimateRates(generation: generation, widthMHz: channelWidthMHz)
        let parsedIE = InformationElementParser.parse(ieData)
        let beaconAirtime = estimateBeaconAirtime(beaconInterval: beaconInterval, beaconRate: rateEstimate.beaconRate)

        let id = makeStableId(
            ssid: ssid, bssid: bssid, channel: channelNumber, band: band, widthMHz: channelWidthMHz, security: security)

        return NetworkModel(
            id: id,
            bssid: bssid,
            ssid: ssid,
            band: band,
            channel: channelNumber,
            channelWidthMHz: channelWidthMHz,
            generation: generation,
            security: security,
            vendor: vendor,
            apName: APNameDetector.name(for: parsedIE.elements, ssid: ssid, vendor: vendor),
            mode: mode,
            signal: rssi,
            noise: noise,
            snr: snr,
            basicRates: rateEstimate.basicRates,
            minBasicRate: rateEstimate.minBasicRate,
            maxBasicRate: rateEstimate.maxBasicRate,
            minRate: rateEstimate.minRate,
            maxRate: rateEstimate.maxRate,
            centerFrequency: centerFrequency,
            channelUtilization: parsedIE.channelUtilization,
            beaconInterval: beaconInterval,
            beaconRate: rateEstimate.beaconRate,
            beaconAirtime: beaconAirtime,
            beaconMode: mode,
            countryCode: countryCode,
            fastTransition: parsedIE.fastTransition,
            protectionMode: parsedIE.protectionMode,
            stations: parsedIE.stations,
            clients: parsedIE.clients ?? parsedIE.stations,
            streams: parsedIE.streams,
            type: mode,
            wps: parsedIE.wpsSummary ?? "Unknown",
            wpsEnabled: parsedIE.wpsEnabled,
            pmfRequired: parsedIE.pmfRequired,
            ieCount: parsedIE.ieCount,
            ieTotalLength: ieTotalLength,
            ratesEstimated: rateEstimate.isEstimated,
            informationElements: parsedIE.elements,
            count: 0,
            firstSeen: nil,
            lastSeen: nil
        )
    }

    private static func makeStableId(
        ssid: String, bssid: String, channel: Int, band: WiFiBand, widthMHz: Int, security: String
    ) -> String {
        if !bssid.isEmpty { return bssid }
        let safeSSID = ssid.isEmpty ? "<Hidden>" : ssid
        return "\(safeSSID)|\(band.rawValue)|\(channel)|\(widthMHz)|\(security)"
    }

    private static func mapBand(_ band: CWChannelBand?) -> WiFiBand {
        switch band {
        case .band2GHz: return .band24
        case .band5GHz: return .band5
        case .band6GHz: return .band6
        default: return .unknown
        }
    }

    private static func wiFi7PHYMode() -> CWPHYMode? {
        CWPHYMode(rawValue: 7)
    }

    private static func mapChannelWidth(_ width: CWChannelWidth?) -> Int {
        switch width {
        case .width20MHz: return 20
        case .width40MHz: return 40
        case .width80MHz: return 80
        case .width160MHz: return 160
        default: return 0
        }
    }

    private static func mapGeneration(_ network: CWNetwork) -> WiFiStandard {
        // 802.11be was added to CWPHYMode in a later SDK. Use its raw value so
        // the app still builds against older Xcode versions and detects Wi-Fi 7
        // at runtime on macOS 15+.
        if #available(macOS 15.0, *),
            let wiFi7Mode = wiFi7PHYMode(),
            network.supportsPHYMode(wiFi7Mode)
        {
            return .mode11be
        }
        if network.supportsPHYMode(.mode11ax) { return .mode11ax }
        if network.supportsPHYMode(.mode11ac) { return .mode11ac }
        if network.supportsPHYMode(.mode11n) { return .mode11n }
        if network.supportsPHYMode(.mode11g) { return .mode11g }
        if network.supportsPHYMode(.mode11a) { return .mode11a }
        if network.supportsPHYMode(.mode11b) { return .mode11b }
        return .unknown
    }

    private static func centerFrequency(channel: Int, band: WiFiBand) -> Int? {
        guard channel > 0 else { return nil }
        switch band {
        case .band24:
            if channel == 14 { return 2484 }
            return 2407 + (channel * 5)
        case .band5:
            return 5000 + (channel * 5)
        case .band6:
            return 5950 + (channel * 5)
        case .unknown:
            return nil
        }
    }

    private struct RateEstimate {
        let basicRates: [Double]?
        let minBasicRate: Double?
        let maxBasicRate: Double?
        let minRate: Double?
        let maxRate: Double?
        let beaconRate: Double?
        let isEstimated: Bool
    }

    private static func estimateRates(generation: WiFiStandard, widthMHz: Int) -> RateEstimate {
        let basicRates: [Double]?
        let minRate: Double?
        let maxRate: Double?

        switch generation {
        case .mode11b:
            basicRates = [1, 2, 5.5, 11]
            minRate = 1
            maxRate = 11
        case .mode11a, .mode11g:
            basicRates = [6, 9, 12, 18, 24, 36, 48, 54]
            minRate = 6
            maxRate = 54
        case .mode11n:
            basicRates = [6, 12, 24, 54]
            minRate = 6
            maxRate = rateFor(widthMHz: widthMHz, defaults: (20, 72), (40, 150), (80, 300), (160, 300))
        case .mode11ac:
            basicRates = [6, 12, 24, 54]
            minRate = 6
            maxRate = rateFor(widthMHz: widthMHz, defaults: (20, 87), (40, 200), (80, 433), (160, 867))
        case .mode11ax:
            basicRates = [6, 12, 24, 54]
            minRate = 6
            maxRate = rateFor(widthMHz: widthMHz, defaults: (20, 143), (40, 286), (80, 600), (160, 1200))
        case .mode11be:
            basicRates = [6, 12, 24, 54]
            minRate = 6
            maxRate = rateFor(widthMHz: widthMHz, defaults: (20, 172), (40, 344), (80, 720), (160, 1440))
        case .unknown:
            basicRates = nil
            minRate = nil
            maxRate = nil
        }

        let minBasicRate = basicRates?.min()
        let maxBasicRate = basicRates?.max()
        let beaconRate = maxBasicRate
        let isEstimated = maxRate != nil || minRate != nil || basicRates != nil

        return RateEstimate(
            basicRates: basicRates,
            minBasicRate: minBasicRate,
            maxBasicRate: maxBasicRate,
            minRate: minRate,
            maxRate: maxRate,
            beaconRate: beaconRate,
            isEstimated: isEstimated
        )
    }

    private static func rateFor(
        widthMHz: Int, defaults: (Int, Double), _ other1: (Int, Double), _ other2: (Int, Double),
        _ other3: (Int, Double)
    ) -> Double? {
        let mapping = [defaults, other1, other2, other3]
        if let match = mapping.first(where: { $0.0 == widthMHz }) {
            return match.1
        }
        let fallback = mapping.first(where: { $0.0 == 20 })?.1 ?? 0
        return fallback > 0 ? fallback : nil
    }

    private static func securityDescription(for network: CWNetwork) -> String {
        let ordered: [(CWSecurity, String)] = [
            (.wpa3Enterprise, "WPA3 Enterprise"),
            (.wpa3Personal, "WPA3 Personal"),
            (.wpa3Transition, "WPA3 Transition"),
            (.oweTransition, "OWE Transition"),
            (.OWE, "OWE"),
            (.wpa2Enterprise, "WPA2 Enterprise"),
            (.wpa2Personal, "WPA2 Personal"),
            (.enterprise, "WPA Enterprise"),
            (.personal, "WPA Personal"),
            (.wpaEnterprise, "WPA Enterprise"),
            (.wpaPersonal, "WPA Personal"),
            (.dynamicWEP, "Dynamic WEP"),
            (.WEP, "WEP"),
            (.none, "Open"),
        ]

        for (security, label) in ordered where network.supportsSecurity(security) {
            return label
        }
        return "Unknown"
    }

    private static func estimateBeaconAirtime(beaconInterval: Int?, beaconRate: Double?) -> Double? {
        guard let beaconInterval, beaconInterval > 0, let beaconRate, beaconRate > 0 else { return nil }
        let beaconSizeBytes = 300.0
        let airtimeMs = (beaconSizeBytes * 8.0) / (beaconRate * 1_000_000.0) * 1000.0
        let beaconsPerSecond = 1000.0 / Double(beaconInterval)
        let airtimePerSecondMs = airtimeMs * beaconsPerSecond
        return airtimePerSecondMs > 0 ? airtimePerSecondMs : nil
    }
}

enum WiFiInterfaceCatalog {
    static func names() -> [String] {
        (CWWiFiClient.shared().interfaceNames() ?? []).sorted()
    }
}
