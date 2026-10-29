import Foundation

enum ChannelAdvisor {
    static func advice(
        for network: NetworkModel, report: AnalysisReport, allNetworks: [NetworkModel]
    ) -> ChannelAdvice? {
        guard network.band != .unknown else { return nil }
        let candidates = NetworkAnalyzer.recommendations(
            for: network.band, among: allNetworks, limit: 100
        )
        guard !candidates.isEmpty else { return nil }

        let current = candidates.first { $0.channel == network.channel }
        let currentIsDFS = current?.isDFS ?? false
        let model = network.routerModel

        let compatible = candidates.filter { supports($0, generation: network.generation) }
        guard !compatible.isEmpty else { return nil }

        // If the router is already on a non-DFS channel, do not suggest a DFS
        // channel: many routers/regions block it and the user would lose the AP.
        let nonDFS = compatible.filter { !$0.isDFS }
        let pool: [ChannelRecommendation]
        if !currentIsDFS, !nonDFS.isEmpty {
            pool = nonDFS
        } else {
            pool = compatible
        }
        guard let recommended = pool.first else { return nil }

        let currentScore = current?.score
        let improvement = recommended.score - (currentScore ?? 0)
        let shouldChange = current == nil || improvement >= 10
        let reason: String
        if !shouldChange {
            reason = "Current channel is already the best available for this router and band."
        } else if currentIsDFS {
            reason = "Current DFS channel is busy; recommended a less loaded supported channel."
        } else if recommended.isDFS {
            reason = "Only DFS channels are less loaded; confirm the router/region allows DFS."
        } else {
            reason = "Less loaded channel for \(network.band.label); DFS candidates were avoided."
        }
        return ChannelAdvice(
            currentChannel: network.channel,
            currentWidthMHz: network.channelWidthMHz,
            currentScore: currentScore,
            recommendation: recommended,
            shouldChange: shouldChange,
            reason: reason,
            routerModel: model
        )
    }

    private static func supports(_ recommendation: ChannelRecommendation, generation: WiFiStandard) -> Bool {
        switch recommendation.band {
        case .band6:
            // 6 GHz requires Wi-Fi 6E/7 (11ax or 11be).
            return generation == .mode11ax || generation == .mode11be
        case .band5:
            // 11b/g are 2.4 GHz-only; 11n/ac/ax/be may use 5 GHz.
            return generation != .mode11b && generation != .mode11g
        case .band24:
            return true
        case .unknown:
            return false
        }
    }
}
