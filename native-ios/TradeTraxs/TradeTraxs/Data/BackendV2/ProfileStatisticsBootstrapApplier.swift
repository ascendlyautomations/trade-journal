import Foundation

nonisolated enum ProfileStatisticsBootstrapApplier {
    struct Applied: Sendable {
        var modeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
    }

    private struct ModeWire: Codable, Sendable {
        var filtered_trade_count: Int
        var win_rate: PostgresFlexibleDouble?
        var profit_factor: PostgresFlexibleDouble?
        var average_winner: PostgresFlexibleDouble?
        var average_loser: PostgresFlexibleDouble?
        var profit_per_trade: PostgresFlexibleDouble?
        var biggest_win: PostgresFlexibleDouble?
        var biggest_loss: PostgresFlexibleDouble?
        var long_trades: Int
        var max_win_streak: Int
        var max_loss_streak: Int
        var session_total: Int
        var session_breakdown: [SessionRowWire]
        var current_equity: PostgresFlexibleDouble?
        var equity_data: [EquityPointWire]
    }

    private struct SessionRowWire: Codable, Sendable {
        var label: String
        var count: Int
        var pct: Double
    }

    private struct EquityPointWire: Codable, Sendable {
        var index: Int
        var equity: PostgresFlexibleDouble?
        var date: String?
    }

    nonisolated static func apply(_ bootstrap: ProfileStatisticsBootstrapV1) -> Applied {
        var results: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result] = [:]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for (key, value) in bootstrap.data.modes {
            guard let mode = mapModeKey(key),
                  let data = try? encoder.encode(value),
                  let wire = try? decoder.decode(ModeWire.self, from: data)
            else { continue }
            results[mode] = mapResult(wire)
        }
        return Applied(modeResults: results)
    }

    private static func mapModeKey(_ raw: String) -> ProfileStatisticsMetrics.Mode? {
        switch raw.lowercased() {
        case "all": return .all
        case "eval": return .eval
        case "funded": return .funded
        case "live": return .live
        case "sim": return .sim
        case "backtest": return .backtest
        default: return nil
        }
    }

    private static func mapResult(_ wire: ModeWire) -> ProfileStatisticsMetrics.Result {
        let equity: [ProfileStatisticsMetrics.EquityPoint] = ProfileStatisticsMetrics.chartOrderedEquityPoints(
            wire.equity_data.map { point in
                ProfileStatisticsMetrics.EquityPoint(
                    index: point.index,
                    equity: point.equity?.decimal ?? 0,
                    date: point.date.flatMap { ISO8601.date(from: $0) }
                )
            }
        )
        let sessions = wire.session_breakdown.map {
            ProfileStatisticsMetrics.SessionRow(label: $0.label, count: $0.count, pct: $0.pct)
        }
        return ProfileStatisticsMetrics.Result(
            filteredTradeCount: wire.filtered_trade_count,
            winRate: wire.win_rate?.decimal,
            profitFactor: wire.profit_factor?.decimal,
            averageWinner: wire.average_winner?.decimal,
            averageLoser: wire.average_loser?.decimal,
            profitPerTrade: wire.profit_per_trade?.decimal,
            biggestWin: wire.biggest_win?.decimal ?? 0,
            biggestLoss: wire.biggest_loss?.decimal,
            longTrades: wire.long_trades,
            maxWinStreak: wire.max_win_streak,
            maxLossStreak: wire.max_loss_streak,
            sessionTotal: wire.session_total,
            sessionBreakdown: sessions,
            currentEquity: wire.current_equity?.decimal ?? 0,
            equityData: equity
        )
    }
}
