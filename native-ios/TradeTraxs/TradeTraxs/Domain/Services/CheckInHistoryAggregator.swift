import Foundation

/// Builds check-in history rows from bulk check-ins + trades — no per-day queries.
nonisolated enum CheckInHistoryAggregator {
    static let defaultDayWindow = 90

    static func buildSummaries(
        checkIns: [TraderDailyCheckIn],
        trades: [Trade],
        dayLimit: Int = defaultDayWindow
    ) -> [CheckInHistoryDaySummary] {
        let checkInByDate = Dictionary(uniqueKeysWithValues: checkIns.map { ($0.checkInDate, $0) })
        var statsByDate: [String: DayStats] = [:]

        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            var stats = statsByDate[key] ?? DayStats()
            stats.tradeCount += 1
            let pnl = trade.realizedPnL?.amount ?? 0
            stats.totalPnL += pnl
            if pnl > 0 { stats.winCount += 1 }
            else if pnl < 0 { stats.lossCount += 1 }
            statsByDate[key] = stats
        }

        var dateKeys = Set(checkInByDate.keys)
        dateKeys.formUnion(statsByDate.keys)

        let sorted = dateKeys.sorted(by: >).prefix(dayLimit)
        return sorted.map { key in
            let stats = statsByDate[key] ?? DayStats()
            return CheckInHistoryDaySummary(
                dateKey: key,
                checkIn: checkInByDate[key],
                tradeCount: stats.tradeCount,
                totalPnL: stats.totalPnL,
                winCount: stats.winCount,
                lossCount: stats.lossCount
            )
        }
    }

    static func buildDetail(
        dateKey: String,
        checkIns: [TraderDailyCheckIn],
        trades: [Trade]
    ) -> CheckInDayDetail {
        let dayTrades = trades.filter {
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0) == dateKey
        }.sorted { $0.entryAt > $1.entryAt }
        let checkIn = checkIns.first { $0.checkInDate == dateKey }
        let metrics = TraderPsychologyAnalyticsEngine.metrics(for: dayTrades)
        return CheckInDayDetail(
            dateKey: dateKey,
            checkIn: checkIn,
            trades: dayTrades,
            metrics: metrics
        )
    }

    static func startDateKey(dayLimit: Int = defaultDayWindow, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(dayLimit - 1), to: calendar.startOfDay(for: now)) ?? now
        return TraderPsychologyAnalyticsFoundation.tradeDateKey(for: start)
    }

    private struct DayStats {
        var tradeCount = 0
        var totalPnL: Decimal = 0
        var winCount = 0
        var lossCount = 0
    }
}
