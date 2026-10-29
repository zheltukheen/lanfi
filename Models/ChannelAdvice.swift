import Foundation

struct ChannelAdvice: Equatable {
    let currentChannel: Int
    let currentWidthMHz: Int
    let currentScore: Int?
    let recommendation: ChannelRecommendation?
    let shouldChange: Bool
    let reason: String
    let routerModel: String?

    var targetChannel: Int? { shouldChange ? recommendation?.channel : nil }
}
