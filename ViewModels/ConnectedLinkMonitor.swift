import CoreWLAN
import Foundation

/// Polls the connected link on a slow 5 s timer for the inspector's Link block.
/// CoreWLAN does not expose MCS/NSS for the live link, so those stay derived
/// from the beacon and are labelled as capability by the view.
@MainActor
final class ConnectedLinkMonitor: ObservableObject {
    static let sampleCapacity = 60
    static let interval: TimeInterval = 5

    @Published private(set) var rssi: Int?
    @Published private(set) var noise: Int?
    @Published private(set) var rateMbps: Double?
    @Published private(set) var channel: Int?
    @Published private(set) var widthMHz: Int?
    @Published private(set) var rateHistory: [LinkRateSample] = []

    private var timer: Timer?
    private let client = CWWiFiClient.shared()

    var summary: LinkTelemetrySummary {
        LinkTelemetrySummary.make(samples: rateHistory)
    }

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func sample() {
        guard let interface = client.interface() else { return }
        rssi = Int(interface.rssiValue())
        let noiseValue = Int(interface.noiseMeasurement())
        noise = noiseValue == 0 ? nil : noiseValue

        let rate = interface.transmitRate()
        rateMbps = rate
        if rate > 0 {
            rateHistory.append(LinkRateSample(at: Date(), rateMbps: rate))
            if rateHistory.count > Self.sampleCapacity {
                rateHistory.removeFirst(rateHistory.count - Self.sampleCapacity)
            }
        }

        if let wlanChannel = interface.wlanChannel() {
            channel = wlanChannel.channelNumber
            widthMHz = Self.widthMHz(for: wlanChannel.channelWidth)
        }
    }

    static func widthMHz(for width: CWChannelWidth) -> Int? {
        switch width {
        case .width20MHz: return 20
        case .width40MHz: return 40
        case .width80MHz: return 80
        case .width160MHz: return 160
        default: return nil
        }
    }
}
