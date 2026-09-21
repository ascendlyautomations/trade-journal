import Foundation

nonisolated enum ProfileAnalyticsModesCodec {
    private struct Payload: Codable {
        var modes: [String: ProfileStatisticsBootstrapModeMapping.ModeWire]
    }

    static func encode(
        _ modes: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result]
    ) throws -> Data {
        var wireModes: [String: ProfileStatisticsBootstrapModeMapping.ModeWire] = [:]
        for (mode, result) in modes {
            wireModes[mode.rawValue] = wire(from: result)
        }
        return try JSONEncoder().encode(Payload(modes: wireModes))
    }

    static func decode(_ data: Data) throws -> [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var out: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result] = [:]
        for (key, wire) in payload.modes {
            guard let mode = modeKey(key) else { continue }
            out[mode] = ProfileStatisticsBootstrapModeMapping.result(from: wire)
        }
        return out
    }

    private static func modeKey(_ raw: String) -> ProfileStatisticsMetrics.Mode? {
        ProfileStatisticsMetrics.Mode(rawValue: raw.lowercased())
    }

    private static func wire(from result: ProfileStatisticsMetrics.Result) -> ProfileStatisticsBootstrapModeMapping.ModeWire {
        ProfileStatisticsBootstrapModeMapping.ModeWire(
            filtered_trade_count: result.filteredTradeCount,
            win_rate: result.winRate.map { PostgresFlexibleDouble(NSDecimalNumber(decimal: $0).doubleValue) },
            profit_factor: result.profitFactor.map { PostgresFlexibleDouble(NSDecimalNumber(decimal: $0).doubleValue) },
            average_winner: result.averageWinner.map { PostgresFlexibleDouble(NSDecimalNumber(decimal: $0).doubleValue) },
            average_loser: result.averageLoser.map { PostgresFlexibleDouble(NSDecimalNumber(decimal: $0).doubleValue) },
            profit_per_trade: result.profitPerTrade.map { PostgresFlexibleDouble(NSDecimalNumber(decimal: $0).doubleValue) },
            biggest_win: PostgresFlexibleDouble(NSDecimalNumber(decimal: result.biggestWin).doubleValue),
            biggest_loss: result.biggestLoss.map { PostgresFlexibleDouble(NSDecimalNumber(decimal: $0).doubleValue) },
            long_trades: result.longTrades,
            max_win_streak: result.maxWinStreak,
            max_loss_streak: result.maxLossStreak,
            session_total: result.sessionTotal,
            session_breakdown: result.sessionBreakdown.map {
                ProfileStatisticsBootstrapModeMapping.SessionRowWire(
                    label: $0.label,
                    count: $0.count,
                    pct: $0.pct
                )
            },
            current_equity: PostgresFlexibleDouble(NSDecimalNumber(decimal: result.currentEquity).doubleValue),
            equity_data: result.equityData.map {
                ProfileStatisticsBootstrapModeMapping.EquityPointWire(
                    index: $0.index,
                    equity: PostgresFlexibleDouble(NSDecimalNumber(decimal: $0.equity).doubleValue),
                    date: $0.date.map { ISO8601.string(from: $0) }
                )
            }
        )
    }
}
