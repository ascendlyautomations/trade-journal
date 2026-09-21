import Foundation

/// Profile Trades outcome filter — matches web `ProfileTradesTab` semantics.
enum ProfileTradesFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case wins
    case losses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .wins: return "Wins"
        case .losses: return "Losses"
        }
    }

    func matches(_ trade: Trade) -> Bool {
        matches(TradeSummaryMapper.summary(fromPartialListTrade: trade))
    }

    func matches(_ summary: TradeSummary) -> Bool {
        switch self {
        case .all:
            return true
        case .wins:
            return (summary.realizedPnL?.amount ?? 0) >= 0
        case .losses:
            return (summary.realizedPnL?.amount ?? 0) < 0
        }
    }
}

/// Profile Trades sort — matches web `TradesSortKey` labels/order.
enum ProfileTradesSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case highestProfit
    case lowestProfit
    case highestRR
    case lowestRR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .highestProfit: return "Highest Profit"
        case .lowestProfit: return "Lowest Profit"
        case .highestRR: return "Highest RR"
        case .lowestRR: return "Lowest RR"
        }
    }

    func sorted(_ trades: [Trade]) -> [Trade] {
        sorted(trades.map(TradeSummaryMapper.summary(fromPartialListTrade:))).map {
            TradeSummaryMapper.previewTrade(from: $0)
        }
    }

    func sorted(_ summaries: [TradeSummary]) -> [TradeSummary] {
        switch self {
        case .newest:
            return summaries.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return summaries.sorted { $0.createdAt < $1.createdAt }
        case .highestProfit:
            return summaries.sorted { lhs, rhs in
                (lhs.realizedPnL?.amount ?? 0) > (rhs.realizedPnL?.amount ?? 0)
            }
        case .lowestProfit:
            return summaries.sorted { lhs, rhs in
                (lhs.realizedPnL?.amount ?? 0) < (rhs.realizedPnL?.amount ?? 0)
            }
        case .highestRR:
            return summaries.sorted { lhs, rhs in
                compareRR(lhs.riskReward, rhs.riskReward, ascending: false)
            }
        case .lowestRR:
            return summaries.sorted { lhs, rhs in
                compareRR(lhs.riskReward, rhs.riskReward, ascending: true)
            }
        }
    }

    private func compareRR(_ lhs: Decimal?, _ rhs: Decimal?, ascending: Bool) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return false
        case (nil, _): return false // nulls last
        case (_, nil): return true
        case let (l?, r?):
            return ascending ? l < r : l > r
        }
    }
}
