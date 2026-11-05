import Foundation

nonisolated enum ScorecardPlanAdherence {
    static let minPostLossPlanTagged = 10
    static let minTripleLossWindowPlanTagged = 5

    enum ObservationSource: String, Sendable {
        case postLoss = "post_loss"
        case tripleLossWindow = "triple_loss_window"
    }

    struct PlanAdherenceObservation: Hashable, Sendable {
        var tradeId: String
        var followed: Bool
        var source: ObservationSource
    }

    static func tripleLossRecoveryIndices(trades: [ScorecardTrade]) -> (start: Int, end: Int)? {
        guard trades.count >= 4 else { return nil }
        for i in 0...(trades.count - 4) {
            if trades[i].pnl < 0, trades[i + 1].pnl < 0, trades[i + 2].pnl < 0 {
                let start = i + 3
                let end = min(trades.count, start + 5)
                guard start < end else { return nil }
                return (start, end)
            }
        }
        return nil
    }

    static func postLossPlanObservations(trades: [ScorecardTrade]) -> [PlanAdherenceObservation] {
        var out: [PlanAdherenceObservation] = []
        guard trades.count > 1 else { return out }
        for i in 1..<trades.count {
            if trades[i - 1].pnl >= 0 { continue }
            let trade = trades[i]
            guard trade.followedPlan != nil else { continue }
            out.append(
                PlanAdherenceObservation(
                    tradeId: trade.id,
                    followed: trade.followedPlan == true,
                    source: .postLoss
                )
            )
        }
        return out
    }

    static func tripleLossWindowPlanObservations(trades: [ScorecardTrade]) -> [PlanAdherenceObservation] {
        guard let window = tripleLossRecoveryIndices(trades: trades) else { return [] }
        var out: [PlanAdherenceObservation] = []
        for i in window.start..<window.end {
            let trade = trades[i]
            guard trade.followedPlan != nil else { continue }
            out.append(
                PlanAdherenceObservation(
                    tradeId: trade.id,
                    followed: trade.followedPlan == true,
                    source: .tripleLossWindow
                )
            )
        }
        return out
    }

    static func consistencyPlanAdherencePool(trades: [ScorecardTrade]) -> (
        observations: [PlanAdherenceObservation],
        postLossCount: Int,
        tripleWindowAddedCount: Int
    ) {
        let postLoss = postLossPlanObservations(trades: trades)
        var byId: [String: PlanAdherenceObservation] = [:]
        for observation in postLoss {
            byId[observation.tradeId] = observation
        }
        let postLossCount = byId.count
        var tripleWindowAddedCount = 0
        if byId.count < minPostLossPlanTagged {
            for observation in tripleLossWindowPlanObservations(trades: trades) {
                if byId[observation.tradeId] == nil {
                    byId[observation.tradeId] = observation
                    tripleWindowAddedCount += 1
                }
            }
        }
        return (Array(byId.values), postLossCount, tripleWindowAddedCount)
    }

    static func planAdherenceRate(observations: [PlanAdherenceObservation]) -> Double? {
        guard !observations.isEmpty else { return nil }
        let followed = observations.filter(\.followed).count
        return Double(followed) / Double(observations.count)
    }
}
