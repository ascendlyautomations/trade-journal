import Foundation

/// Joins per-trade psychology with owner-only daily check-ins for future analytics.
/// Does not produce user-facing insights — data foundation only.
nonisolated enum TraderPsychologyAnalyticsFoundation {
    /// Eastern trade-date key — same as `trades.trade_date` and `check_in_date`.
    static func tradeDateKey(for trade: Trade) -> String {
        TradingSessionLabel.easternTradeDateString(from: trade.entryAt)
    }

    static func tradeDateKey(for date: Date) -> String {
        TradingSessionLabel.easternTradeDateString(from: date)
    }

    static func todayCheckInDateKey(now: Date = Date()) -> String {
        tradeDateKey(for: now)
    }

    struct TradeDailyContext: Hashable, Sendable {
        var trade: Trade
        var dailyCheckIn: TraderDailyCheckIn?
    }

    /// Index check-ins by Eastern date, then attach to each trade on the same date.
    static func correlate(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [TradeDailyContext] {
        let byDate = Dictionary(
            uniqueKeysWithValues: checkIns.map { ($0.checkInDate, $0) }
        )
        return trades.map { trade in
            TradeDailyContext(
                trade: trade,
                dailyCheckIn: byDate[tradeDateKey(for: trade)]
            )
        }
    }

    /// Sleep-hour bands for future P&L / win-rate / expectancy breakdowns.
    enum SleepHoursBand: String, CaseIterable, Sendable {
        case underSix = "<6h"
        case sixToSeven = "6–7h"
        case sevenToNine = "7–9h"
        case ninePlus = "9h+"

        static func resolve(_ hours: Decimal?) -> SleepHoursBand? {
            guard let hours else { return nil }
            let value = NSDecimalNumber(decimal: hours).doubleValue
            if value < 6 { return .underSix }
            if value < 7 { return .sixToSeven }
            if value <= 9 { return .sevenToNine }
            return .ninePlus
        }
    }

    enum RatingBand: String, Sendable {
        case low = "1–2"
        case mid = "3"
        case high = "4–5"

        static func resolve(_ rating: Int?) -> RatingBand? {
            guard let rating else { return nil }
            switch rating {
            case 1...2: return .low
            case 3: return .mid
            case 4...5: return .high
            default: return nil
            }
        }
    }

    /// Automatically derived streak context — never user-entered.
    struct TradeBehaviorSnapshot: Hashable, Sendable {
        var consecutiveWins: Int
        var consecutiveLosses: Int
        var recentNetPnL: Decimal
    }

    static func behaviorSnapshot(
        for trades: [Trade],
        endingAt tradeID: TradeID
    ) -> TradeBehaviorSnapshot? {
        let sorted = trades.sorted { $0.entryAt < $1.entryAt }
        guard let index = sorted.firstIndex(where: { $0.id == tradeID }) else {
            return nil
        }
        let prefix = Array(sorted.prefix(through: index))
        var wins = 0
        var losses = 0
        for trade in prefix.reversed() {
            guard let pnl = trade.realizedPnL?.amount else { break }
            if pnl > 0 {
                if losses > 0 { break }
                wins += 1
            } else if pnl < 0 {
                if wins > 0 { break }
                losses += 1
            } else {
                break
            }
        }
        let recentNet = prefix.suffix(5).compactMap(\.realizedPnL?.amount).reduce(0, +)
        return TradeBehaviorSnapshot(
            consecutiveWins: wins,
            consecutiveLosses: losses,
            recentNetPnL: recentNet
        )
    }
}
