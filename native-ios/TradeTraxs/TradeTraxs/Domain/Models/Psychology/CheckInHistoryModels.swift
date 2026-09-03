import Foundation

/// One row in Check-In History — Eastern trading date + optional check-in + day trade stats.
nonisolated struct CheckInHistoryDaySummary: Identifiable, Hashable, Sendable {
    var id: String { dateKey }
    var dateKey: String
    var checkIn: TraderDailyCheckIn?
    var tradeCount: Int
    var totalPnL: Decimal
    var winCount: Int
    var lossCount: Int

    var winRate: Decimal? {
        guard tradeCount > 0 else { return nil }
        return Decimal(winCount) / Decimal(tradeCount)
    }

    var hasCheckIn: Bool { checkIn != nil }
    var hasTrades: Bool { tradeCount > 0 }
}

/// Detail payload for a single Eastern trading day.
nonisolated struct CheckInDayDetail: Hashable, Sendable {
    var dateKey: String
    var checkIn: TraderDailyCheckIn?
    var trades: [Trade]
    var metrics: PsychologyGroupMetrics
}
