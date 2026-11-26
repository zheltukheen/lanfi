import Foundation

/// G7: what one BSSID cost the channel in a capture, measured from the
/// Duration/ID field of the frames it transmitted.
public struct ChannelAirtimeEntry: Identifiable, Equatable, Sendable {
    public let bssid: String
    public let ssid: String
    public var frames: Int
    public var airtimeMicroseconds: Int
    public var dataFrames: Int
    /// Directed data frames transmitted at 1, 2, 5.5 or 11 Mbit/s.
    public var legacyFrames: Int
    /// Share of all transmitted airtime in this capture, when any frame carried
    /// a duration.
    public var share: Double?

    public init(
        bssid: String, ssid: String, frames: Int = 0, airtimeMicroseconds: Int = 0,
        dataFrames: Int = 0, legacyFrames: Int = 0, share: Double? = nil
    ) {
        self.bssid = bssid
        self.ssid = ssid
        self.frames = frames
        self.airtimeMicroseconds = airtimeMicroseconds
        self.dataFrames = dataFrames
        self.legacyFrames = legacyFrames
        self.share = share
    }

    public var id: String { bssid }
    public var airtimeMilliseconds: Int { airtimeMicroseconds / 1000 }
    public var isLegacy: Bool { legacyFrames > 0 }
}
