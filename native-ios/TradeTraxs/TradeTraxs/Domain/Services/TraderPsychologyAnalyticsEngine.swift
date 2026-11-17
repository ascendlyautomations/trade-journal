import Foundation

/// Deterministic psychology-performance analytics — no AI, no persisted streak columns.
nonisolated enum TraderPsychologyAnalyticsEngine {
    // MARK: - Public entry

    static func buildReport(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> PsychologyAnalyticsReport {
        let enriched = enrich(trades: trades, checkIns: checkIns)
        let baseline = metrics(for: enriched.map(\.trade))
        let comparison = PsychologyComparisonBuilder.build(enriched: enriched, preferences: preferences)
        let matchedTrades = enriched.filter { $0.dailyCheckIn != nil }.count

        return PsychologyAnalyticsReport(
            generatedAt: now,
            baseline: baseline,
            dashboardCards: comparison.insights,
            sections: comparison.sections,
            enrichedTradeCount: enriched.count,
            checkInMatchedTradeCount: matchedTrades,
            matchedDayCount: PsychologyComparisonBuilder.matchedDayCount(trades: trades, checkIns: checkIns)
        )
    }

    // MARK: - Enrichment

    static func enrich(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [PsychologyEnrichedTrade] {
        let correlated = TraderPsychologyAnalyticsFoundation.correlate(
            trades: trades,
            checkIns: checkIns
        )
        let chronological = correlated.sorted { $0.trade.entryAt < $1.trade.entryAt }

        var consecutiveLosses = 0
        var consecutiveWins = 0
        var dayCounts: [String: Int] = [:]

        return chronological.map { context in
            let dayKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: context.trade)
            let nextNumber = (dayCounts[dayKey] ?? 0) + 1
            dayCounts[dayKey] = nextNumber

            let previousLoss = consecutiveLosses > 0
            let snapshot = PsychologyEnrichedTrade(
                trade: context.trade,
                dailyCheckIn: context.dailyCheckIn,
                consecutiveLossesBefore: consecutiveLosses,
                consecutiveWinsBefore: consecutiveWins,
                tradeNumberInDay: nextNumber,
                previousTradeWasLoss: previousLoss
            )

            switch pnlSign(context.trade) {
            case .win:
                consecutiveWins += 1
                consecutiveLosses = 0
            case .loss:
                consecutiveLosses += 1
                consecutiveWins = 0
            case .flat:
                break
            }

            return snapshot
        }
    }

    // MARK: - Metrics

    static func metrics(for trades: [Trade]) -> PsychologyGroupMetrics {
        guard !trades.isEmpty else { return .empty }

        let known = trades.compactMap(\.realizedPnL?.amount)
        let wins = known.filter { $0 > 0 }
        let losses = known.filter { $0 < 0 }
        let tradeCount = trades.count
        let knownCount = known.count
        let winCount = wins.count
        let lossCount = losses.count

        let grossWins = wins.reduce(0, +)
        let grossLosses = losses.reduce(0, +)
        let totalPnL = known.reduce(0, +)
        let winRate: Decimal? = knownCount > 0 ? Decimal(winCount) / Decimal(knownCount) : nil
        let avgWin = winCount > 0 ? grossWins / Decimal(winCount) : nil
        let avgLossAbs = lossCount > 0 ? abs(grossLosses) / Decimal(lossCount) : nil
        let lossRate = knownCount > 0 ? Decimal(lossCount) / Decimal(knownCount) : 0
        let winRateFrac = winRate ?? 0
        let expectancy: Decimal? = knownCount > 0
            ? winRateFrac * (avgWin ?? 0) - lossRate * (avgLossAbs ?? 0)
            : nil
        let profitFactor: Decimal? = grossLosses < 0 ? grossWins / abs(grossLosses) : nil

        var rrSum = Decimal(0)
        var rrCount = 0
        for trade in trades {
            guard let rr = trade.riskReward else { continue }
            rrSum += rr
            rrCount += 1
        }

        return PsychologyGroupMetrics(
            tradeCount: tradeCount,
            winCount: winCount,
            lossCount: lossCount,
            winRate: winRate,
            totalPnL: totalPnL,
            averagePnL: knownCount > 0 ? totalPnL / Decimal(knownCount) : nil,
            expectancy: expectancy,
            averageRR: rrCount > 0 ? rrSum / Decimal(rrCount) : nil,
            profitFactor: profitFactor,
            reliability: PsychologySampleReliability.resolve(tradeCount: tradeCount)
        )
    }

    // MARK: - Sleep bands

    enum SleepPerformanceBand: String, CaseIterable, Sendable {
        case underFive = "<5h"
        case fiveToSix = "5–6h"
        case sixToSeven = "6–7h"
        case sevenToEight = "7–8h"
        case eightToNine = "8–9h"
        case ninePlus = "9h+"

        static func resolve(_ hours: Decimal?) -> SleepPerformanceBand? {
            guard let hours else { return nil }
            let value = NSDecimalNumber(decimal: hours).doubleValue
            if value < 5 { return .underFive }
            if value < 6 { return .fiveToSix }
            if value < 7 { return .sixToSeven }
            if value < 8 { return .sevenToEight }
            if value <= 9 { return .eightToNine }
            return .ninePlus
        }
    }

    enum DailyRatingDimension: String, CaseIterable, Sendable {
        case sleepQuality
        case morningRating
        case stress
        case energy
        case focus

        var title: String {
            switch self {
            case .sleepQuality: return "Sleep Quality"
            case .morningRating: return "Morning"
            case .stress: return "Stress"
            case .energy: return "Energy"
            case .focus: return "Focus"
            }
        }

        func rating(from checkIn: TraderDailyCheckIn) -> Int? {
            switch self {
            case .sleepQuality: return checkIn.sleepQuality
            case .morningRating: return checkIn.morningRating
            case .stress: return checkIn.stressLevel
            case .energy: return checkIn.energyLevel
            case .focus: return checkIn.focusLevel
            }
        }

        /// Higher score = better trading condition for positive metrics; stress is inverted (lower is better).
        var higherIsBetter: Bool {
            switch self {
            case .stress: return false
            default: return true
            }
        }
    }

    enum ConsecutiveLossBucket: String, CaseIterable, Sendable {
        case none = "0 prior losses"
        case one = "1 prior loss"
        case two = "2 prior losses"
        case threePlus = "3+ prior losses"

        static func resolve(_ losses: Int) -> ConsecutiveLossBucket {
            switch losses {
            case 0: return .none
            case 1: return .one
            case 2: return .two
            default: return .threePlus
            }
        }
    }

    enum TradeSequenceBucket: String, CaseIterable, Sendable {
        case first = "Trade #1"
        case second = "Trade #2"
        case third = "Trade #3"
        case fourth = "Trade #4"
        case fifthPlus = "Trade #5+"

        static func resolve(_ number: Int) -> TradeSequenceBucket {
            switch number {
            case 1: return .first
            case 2: return .second
            case 3: return .third
            case 4: return .fourth
            default: return .fifthPlus
            }
        }
    }

    enum ConvictionLevel: Int, CaseIterable, Sendable {
        case one = 1, two, three, four, five
    }

    // MARK: - Ranking

    static func rankInsights(_ candidates: [PsychologyInsightCard]) -> [PsychologyInsightCard] {
        candidates
            .filter { $0.reliability.qualifiesForDashboardCard }
            .sorted { $0.rankingScore > $1.rankingScore }
    }

    // MARK: - Helpers

    private enum PnLSign { case win, loss, flat }

    private static func pnlSign(_ trade: Trade) -> PnLSign {
        guard let pnl = trade.realizedPnL?.amount else { return .flat }
        if pnl > 0 { return .win }
        if pnl < 0 { return .loss }
        return .flat
    }

    static func formatWinRate(_ rate: Decimal?) -> String {
        guard let rate else { return "—" }
        return NumberDisplay.percent(rate * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)
    }

    static func money(_ value: Decimal) -> String {
        NumberDisplay.currency(value, minimumFractionDigits: 0, maximumFractionDigits: 0)
    }

    /// Nil when P&L was not recorded. A real zero still formats as currency.
    static func optionalMoney(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        return money(value)
    }
}
