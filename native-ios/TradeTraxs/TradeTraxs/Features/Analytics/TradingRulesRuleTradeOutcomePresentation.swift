import Foundation

/// UI-only grouping of existing compliance checks (does not re-run the engine).
enum TradingRulesRuleTradeOutcomePresentation {
    struct TradeRow: Identifiable, Sendable, Hashable {
        var id: String { tradeID }
        var tradeID: String
        var at: Date
        var netPnl: Double?
        var detail: String
    }

    struct GroupedOutcomes: Sendable {
        var followed: [TradeRow]
        var violated: [TradeRow]

        var followedCount: Int { followed.count }
        var violatedCount: Int { violated.count }
        var total: Int { followedCount + violatedCount }
    }

    static func groupedTradeOutcomes(
        ruleID: TradingRulesComplianceAnalytics.RuleID,
        checks: [TradingRulesComplianceAnalytics.Check]
    ) -> GroupedOutcomes {
        var followedSeen = Set<String>()
        var violatedSeen = Set<String>()
        var followed: [TradeRow] = []
        var violated: [TradeRow] = []

        for check in checks where check.ruleID == ruleID && check.level == .trade {
            guard let tradeID = check.tradeID else { continue }
            switch check.outcome {
            case .followed:
                guard followedSeen.insert(tradeID).inserted else { continue }
                followed.append(
                    TradeRow(
                        tradeID: tradeID,
                        at: check.at,
                        netPnl: check.pnl,
                        detail: check.detail
                    )
                )
            case .violated:
                guard violatedSeen.insert(tradeID).inserted else { continue }
                violated.append(
                    TradeRow(
                        tradeID: tradeID,
                        at: check.at,
                        netPnl: check.pnl,
                        detail: check.detail
                    )
                )
            case .unevaluated, .notApplicable:
                break
            }
        }

        followed.sort { $0.at > $1.at }
        violated.sort { $0.at > $1.at }
        return GroupedOutcomes(followed: followed, violated: violated)
    }
}