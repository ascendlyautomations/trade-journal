import Foundation

/// Deterministic psychology-performance analytics — no AI, no persisted streak columns.
nonisolated enum TraderPsychologyAnalyticsEngine {
    // MARK: - Public entry

    static func buildReport(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date = Date()
    ) -> PsychologyAnalyticsReport {
        let enriched = enrich(trades: trades, checkIns: checkIns)
        let baseline = metrics(for: enriched.map(\.trade))
        let matchedCount = enriched.filter { $0.dailyCheckIn != nil }.count

        var candidates: [PsychologyInsightCard] = []
        candidates.append(contentsOf: sleepInsights(enriched: enriched, baseline: baseline))
        candidates.append(contentsOf: ratingInsights(enriched: enriched, baseline: baseline))
        candidates.append(contentsOf: convictionInsights(enriched: enriched, baseline: baseline))
        candidates.append(contentsOf: followedPlanInsights(enriched: enriched, baseline: baseline))
        candidates.append(contentsOf: emotionInsights(enriched: enriched, baseline: baseline))
        candidates.append(contentsOf: consecutiveLossInsights(enriched: enriched, baseline: baseline))
        candidates.append(contentsOf: tradeFrequencyInsights(enriched: enriched, baseline: baseline))
        candidates.append(contentsOf: combinedInsights(enriched: enriched, baseline: baseline))

        let ranked = rankInsights(candidates)
        let dashboardCards = Array(ranked.prefix(5))

        let sections = buildSections(
            enriched: enriched,
            baseline: baseline,
            allCandidates: ranked
        )

        return PsychologyAnalyticsReport(
            generatedAt: now,
            baseline: baseline,
            dashboardCards: dashboardCards,
            sections: sections,
            enrichedTradeCount: enriched.count,
            checkInMatchedTradeCount: matchedCount
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

        let pnls = trades.map { $0.realizedPnL?.amount ?? 0 }
        let wins = pnls.filter { $0 > 0 }
        let losses = pnls.filter { $0 < 0 }
        let tradeCount = trades.count
        let winCount = wins.count
        let lossCount = losses.count

        let grossWins = wins.reduce(0, +)
        let grossLosses = losses.reduce(0, +)
        let totalPnL = pnls.reduce(0, +)
        let winRate: Decimal? = tradeCount > 0 ? Decimal(winCount) / Decimal(tradeCount) : nil
        let avgWin = winCount > 0 ? grossWins / Decimal(winCount) : nil
        let avgLossAbs = lossCount > 0 ? abs(grossLosses) / Decimal(lossCount) : nil
        let lossRate = tradeCount > 0 ? Decimal(lossCount) / Decimal(tradeCount) : 0
        let winRateFrac = winRate ?? 0
        let expectancy: Decimal? = tradeCount > 0
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
            averagePnL: totalPnL / Decimal(tradeCount),
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

        /// Higher score = better trading condition except stress.
        var higherIsBetter: Bool {
            self != .stress
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

    // MARK: - Insight builders

    private static func sleepInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        let withSleep = enriched.filter {
            $0.dailyCheckIn?.sleepHours != nil
        }
        guard !withSleep.isEmpty else { return [] }

        let grouped = Dictionary(grouping: withSleep) { item -> SleepPerformanceBand in
            SleepPerformanceBand.resolve(item.dailyCheckIn?.sleepHours) ?? .underFive
        }

        let metricsByBand = SleepPerformanceBand.allCases.compactMap { band -> (SleepPerformanceBand, PsychologyGroupMetrics)? in
            guard let items = grouped[band], !items.isEmpty else { return nil }
            return (band, metrics(for: items.map(\.trade)))
        }.filter { $0.1.reliability.qualifiesForDashboardCard }

        guard metricsByBand.count >= 2 else { return [] }

        let best = metricsByBand.max { lhs, rhs in
            (lhs.1.expectancy ?? lhs.1.averagePnL ?? Decimal(-999_999))
                < (rhs.1.expectancy ?? rhs.1.averagePnL ?? Decimal(-999_999))
        }
        let worst = metricsByBand.min { lhs, rhs in
            (lhs.1.expectancy ?? lhs.1.averagePnL ?? Decimal(999_999))
                < (rhs.1.expectancy ?? rhs.1.averagePnL ?? Decimal(999_999))
        }

        guard let best, let worst, best.0 != worst.0 else { return [] }

        let bestExp = best.1.expectancy ?? best.1.averagePnL ?? 0
        let worstExp = worst.1.expectancy ?? worst.1.averagePnL ?? 0
        let delta = abs(NSDecimalNumber(decimal: bestExp - worstExp).doubleValue)
        guard delta >= 5 || best.1.reliability.qualifiesForComparison else { return [] }

        let headline = "Best performance at \(best.0.rawValue)"
        let detail: String
        if best.1.reliability.qualifiesForComparison, worst.1.reliability.qualifiesForComparison {
            detail = "Your data shows \(money(bestExp)) expectancy at \(best.0.rawValue) versus \(money(worstExp)) at \(worst.0.rawValue) • \(best.1.tradeCount) trades"
        } else {
            detail = "\(money(bestExp)) expectancy • \(best.1.tradeCount) trades • \(best.1.reliability.label)"
        }

        return [
            makeCard(
                id: "sleep.best",
                category: .sleep,
                sectionTitle: "Sleep",
                headline: headline,
                detail: detail,
                metrics: best.1,
                magnitude: delta,
                actionability: 0.9
            ),
        ]
    }

    private static func ratingInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        var cards: [PsychologyInsightCard] = []
        for dimension in DailyRatingDimension.allCases {
            if let card = ratingInsight(
                dimension: dimension,
                enriched: enriched,
                baseline: baseline
            ) {
                cards.append(card)
            }
        }
        return cards
    }

    private static func ratingInsight(
        dimension: DailyRatingDimension,
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> PsychologyInsightCard? {
        let withRating = enriched.compactMap { item -> (PsychologyEnrichedTrade, Int)? in
            guard let checkIn = item.dailyCheckIn,
                  let rating = dimension.rating(from: checkIn)
            else { return nil }
            return (item, rating)
        }
        guard !withRating.isEmpty else { return nil }

        let byRating = Dictionary(grouping: withRating, by: { $0.1 })
        let ratingMetrics = (1...5).compactMap { rating -> (Int, PsychologyGroupMetrics)? in
            guard let rows = byRating[rating] else { return nil }
            let m = metrics(for: rows.map(\.0.trade))
            guard m.reliability.qualifiesForDashboardCard else { return nil }
            return (rating, m)
        }
        guard ratingMetrics.count >= 2 else {
            return groupedRatingInsight(dimension: dimension, withRating: withRating, baseline: baseline)
        }

        let sorted: [(Int, PsychologyGroupMetrics)]
        if dimension.higherIsBetter {
            sorted = ratingMetrics.sorted { $0.0 > $1.0 }
        } else {
            sorted = ratingMetrics.sorted { $0.0 < $1.0 }
        }

        guard let best = sorted.first, let worst = sorted.last, best.0 != worst.0 else { return nil }
        let bestExp = best.1.expectancy ?? best.1.averagePnL ?? 0
        let worstExp = worst.1.expectancy ?? worst.1.averagePnL ?? 0
        let delta = abs(NSDecimalNumber(decimal: bestExp - worstExp).doubleValue)
        guard delta >= 5 else { return nil }

        let bestLabel = dimension.higherIsBetter ? "high" : "low"
        let headline = dimension.higherIsBetter
            ? "Higher \(dimension.title.lowercased()) associated with better results"
            : "Lower \(dimension.title.lowercased()) associated with better results"

        let wrBest = formatWinRate(best.1.winRate)
        let wrWorst = formatWinRate(worst.1.winRate)
        let detail = "Rating \(best.0)/5 (\(wrBest) win rate) vs \(worst.0)/5 (\(wrWorst)) • \(best.1.tradeCount) vs \(worst.1.tradeCount) trades"

        return makeCard(
            id: "rating.\(dimension.rawValue)",
            category: .mentalState,
            sectionTitle: dimension.title,
            headline: headline,
            detail: detail,
            metrics: best.1,
            magnitude: delta,
            actionability: dimension == .stress || dimension == .focus ? 0.85 : 0.75
        )
    }

    private static func groupedRatingInsight(
        dimension: DailyRatingDimension,
        withRating: [(PsychologyEnrichedTrade, Int)],
        baseline: PsychologyGroupMetrics
    ) -> PsychologyInsightCard? {
        enum Band: String { case low = "1–2", mid = "3", high = "4–5" }
        let grouped = Dictionary(grouping: withRating) { pair -> Band in
            switch pair.1 {
            case 1...2: return .low
            case 3: return .mid
            default: return .high
            }
        }

        let bandMetrics = [Band.low, .mid, .high].compactMap { band -> (Band, PsychologyGroupMetrics)? in
            guard let rows = grouped[band] else { return nil }
            let m = metrics(for: rows.map(\.0.trade))
            guard m.reliability.qualifiesForDashboardCard else { return nil }
            return (band, m)
        }
        guard bandMetrics.count >= 2 else { return nil }

        let best: (Band, PsychologyGroupMetrics)
        let worst: (Band, PsychologyGroupMetrics)
        if dimension.higherIsBetter {
            best = bandMetrics.max { ($0.1.expectancy ?? 0) < ($1.1.expectancy ?? 0) }!
            worst = bandMetrics.min { ($0.1.expectancy ?? 0) < ($1.1.expectancy ?? 0) }!
        } else {
            best = bandMetrics.min { ($0.1.expectancy ?? 0) < ($1.1.expectancy ?? 0) }!
            worst = bandMetrics.max { ($0.1.expectancy ?? 0) < ($1.1.expectancy ?? 0) }!
        }

        let delta = abs(NSDecimalNumber(decimal: (best.1.expectancy ?? 0) - (worst.1.expectancy ?? 0)).doubleValue)
        guard delta >= 5 else { return nil }

        return makeCard(
            id: "rating.group.\(dimension.rawValue)",
            category: .mentalState,
            sectionTitle: dimension.title,
            headline: "\(dimension.title) \(best.0.rawValue) band leads your sample",
            detail: "\(money(best.1.expectancy ?? best.1.averagePnL ?? 0)) expectancy (\(best.1.tradeCount) trades) vs \(money(worst.1.expectancy ?? worst.1.averagePnL ?? 0)) (\(worst.1.tradeCount) trades)",
            metrics: best.1,
            magnitude: delta,
            actionability: 0.7
        )
    }

    private static func convictionInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        let withConviction = enriched.compactMap { item -> (PsychologyEnrichedTrade, Int)? in
            guard let confidence = item.trade.confidence, (1...5).contains(confidence) else { return nil }
            return (item, confidence)
        }
        guard !withConviction.isEmpty else { return [] }

        let low = withConviction.filter { (1...2).contains($0.1) }
        let high = withConviction.filter { (4...5).contains($0.1) }
        let lowMetrics = metrics(for: low.map(\.0.trade))
        let highMetrics = metrics(for: high.map(\.0.trade))

        guard lowMetrics.reliability.qualifiesForDashboardCard,
              highMetrics.reliability.qualifiesForDashboardCard
        else { return [] }

        let highWR = formatWinRate(highMetrics.winRate)
        let lowWR = formatWinRate(lowMetrics.winRate)
        let delta = abs(NSDecimalNumber(decimal: (highMetrics.expectancy ?? 0) - (lowMetrics.expectancy ?? 0)).doubleValue)

        let headline = (highMetrics.expectancy ?? 0) >= (lowMetrics.expectancy ?? 0)
            ? "High-conviction trades outperform"
            : "Lower conviction trades outperform in your sample"

        let detail = "Conviction 4–5: \(highWR) win rate (\(highMetrics.tradeCount) trades) vs 1–2: \(lowWR) (\(lowMetrics.tradeCount) trades)"

        return [
            makeCard(
                id: "conviction.highVsLow",
                category: .conviction,
                sectionTitle: "Conviction",
                headline: headline,
                detail: detail,
                metrics: highMetrics,
                magnitude: max(delta, 1),
                actionability: 0.8
            ),
        ]
    }

    private static func followedPlanInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        let followed = enriched.filter { $0.trade.followedPlan == true }
        let notFollowed = enriched.filter { $0.trade.followedPlan == false }
        guard !followed.isEmpty, !notFollowed.isEmpty else { return [] }

        let followedMetrics = metrics(for: followed.map(\.trade))
        let brokenMetrics = metrics(for: notFollowed.map(\.trade))
        guard followedMetrics.reliability.qualifiesForDashboardCard,
              brokenMetrics.reliability.qualifiesForDashboardCard
        else { return [] }

        let followedAvg = followedMetrics.averagePnL ?? 0
        let brokenAvg = brokenMetrics.averagePnL ?? 0
        let delta = abs(NSDecimalNumber(decimal: followedAvg - brokenAvg).doubleValue)
        guard delta >= 5 else { return [] }

        return [
            makeCard(
                id: "discipline.followedPlan",
                category: .discipline,
                sectionTitle: "Discipline",
                headline: "Following your plan matters",
                detail: "Plan followed: \(money(followedAvg)) avg (\(followedMetrics.tradeCount) trades) vs not followed: \(money(brokenAvg)) (\(brokenMetrics.tradeCount) trades)",
                metrics: followedMetrics,
                magnitude: delta,
                actionability: 0.95
            ),
        ]
    }

    private static func emotionInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        let normalized = enriched.compactMap { item -> (PsychologyEnrichedTrade, String)? in
            guard let emotion = normalizedEmotion(item.trade.emotion) else { return nil }
            return (item, emotion)
        }
        let grouped = Dictionary(grouping: normalized, by: \.1)
        let emotionMetrics = TradeReviewCatalog.emotions.compactMap { emotion -> (String, PsychologyGroupMetrics)? in
            guard let rows = grouped[emotion] else { return nil }
            let m = metrics(for: rows.map(\.0.trade))
            guard m.reliability.qualifiesForDashboardCard else { return nil }
            return (emotion, m)
        }
        guard emotionMetrics.count >= 2 else { return [] }

        let worst = emotionMetrics.min {
            ($0.1.expectancy ?? $0.1.averagePnL ?? Decimal(999_999))
                < ($1.1.expectancy ?? $1.1.averagePnL ?? Decimal(999_999))
        }
        let best = emotionMetrics.max {
            ($0.1.expectancy ?? $0.1.averagePnL ?? Decimal(-999_999))
                < ($1.1.expectancy ?? $1.1.averagePnL ?? Decimal(-999_999))
        }
        guard let worst, let best, worst.0 != best.0 else { return [] }

        let delta = abs(NSDecimalNumber(decimal: (best.1.expectancy ?? 0) - (worst.1.expectancy ?? 0)).doubleValue)
        guard delta >= 5 else { return [] }

        return [
            makeCard(
                id: "emotion.\(worst.0.lowercased())",
                category: .emotion,
                sectionTitle: "Emotion",
                headline: "\(worst.0) entries show your weakest expectancy",
                detail: "\(worst.0): \(money(worst.1.expectancy ?? worst.1.averagePnL ?? 0)) expectancy • \(worst.1.tradeCount) trades",
                metrics: worst.1,
                magnitude: delta,
                actionability: 0.75
            ),
        ]
    }

    private static func consecutiveLossInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        let grouped = Dictionary(grouping: enriched) {
            ConsecutiveLossBucket.resolve($0.consecutiveLossesBefore)
        }

        guard let baselineBucket = grouped[.none], baselineBucket.count >= 5 else { return [] }
        let baselineMetrics = metrics(for: baselineBucket.map(\.trade))

        let afterTwo = grouped[.two] ?? []
        let afterThreePlus = grouped[.threePlus] ?? []
        let stressed = afterTwo + afterThreePlus
        guard stressed.count >= 5 else { return [] }

        let stressedMetrics = metrics(for: stressed.map(\.trade))
        guard stressedMetrics.reliability.qualifiesForDashboardCard else { return [] }

        let baseWR = baselineMetrics.winRate ?? 0
        let stressedWR = stressedMetrics.winRate ?? 0
        let delta = abs(NSDecimalNumber(decimal: baseWR - stressedWR).doubleValue)

        let headline: String
        let detail: String
        if stressedWR < baseWR - Decimal(0.05) {
            headline = "Performance drops after multiple losses"
            detail = "\(formatWinRate(stressedWR)) win rate after 2+ losses vs \(formatWinRate(baseWR)) baseline • \(stressedMetrics.tradeCount) trades"
        } else {
            headline = "Your performance stays stable after losses"
            detail = "\(formatWinRate(stressedWR)) win rate after 2+ losses vs \(formatWinRate(baseWR)) baseline • \(stressedMetrics.tradeCount) trades"
        }

        return [
            makeCard(
                id: "afterLosses.streak",
                category: .afterLosses,
                sectionTitle: "After Losses",
                headline: headline,
                detail: detail,
                metrics: stressedMetrics,
                magnitude: max(delta * 100, 1),
                actionability: 0.9
            ),
        ]
    }

    private static func tradeFrequencyInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        let grouped = Dictionary(grouping: enriched) {
            TradeSequenceBucket.resolve($0.tradeNumberInDay)
        }

        let early = (grouped[.first] ?? []) + (grouped[.second] ?? []) + (grouped[.third] ?? [])
        let late = grouped[.fifthPlus] ?? []
        guard early.count >= 5, late.count >= 5 else { return [] }

        let earlyMetrics = metrics(for: early.map(\.trade))
        let lateMetrics = metrics(for: late.map(\.trade))
        guard earlyMetrics.reliability.qualifiesForDashboardCard,
              lateMetrics.reliability.qualifiesForDashboardCard
        else { return [] }

        let earlyAvg = earlyMetrics.averagePnL ?? 0
        let lateAvg = lateMetrics.averagePnL ?? 0
        let delta = abs(NSDecimalNumber(decimal: earlyAvg - lateAvg).doubleValue)
        guard delta >= 5 else { return [] }

        let headline = earlyAvg >= lateAvg
            ? "Early-day trades outperform later ones"
            : "Later trades outperform your openers"

        return [
            makeCard(
                id: "frequency.earlyVsLate",
                category: .tradeFrequency,
                sectionTitle: "Trade Frequency",
                headline: headline,
                detail: "Trades 1–3 avg \(money(earlyAvg)) (\(earlyMetrics.tradeCount) trades) vs trade #5+ avg \(money(lateAvg)) (\(lateMetrics.tradeCount) trades)",
                metrics: earlyMetrics,
                magnitude: delta,
                actionability: 0.85
            ),
        ]
    }

    private static func combinedInsights(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics
    ) -> [PsychologyInsightCard] {
        var cards: [PsychologyInsightCard] = []

        // Low sleep (<6h) + high stress (4–5)
        let lowSleepHighStress = enriched.filter { item in
            guard let checkIn = item.dailyCheckIn,
                  let hours = checkIn.sleepHours,
                  let stress = checkIn.stressLevel
            else { return false }
            return NSDecimalNumber(decimal: hours).doubleValue < 6 && stress >= 4
        }
        if lowSleepHighStress.count >= 10 {
            let combined = metrics(for: lowSleepHighStress.map(\.trade))
            let lowSleepOnly = enriched.filter {
                guard let hours = $0.dailyCheckIn?.sleepHours else { return false }
                return NSDecimalNumber(decimal: hours).doubleValue < 6
            }
            let comparison = metrics(for: lowSleepOnly.map(\.trade))
            if combined.reliability.qualifiesForComparison,
               comparison.reliability.qualifiesForComparison {
                let delta = abs(NSDecimalNumber(decimal: (combined.expectancy ?? 0) - (comparison.expectancy ?? 0)).doubleValue)
                if delta >= 10 {
                    cards.append(
                        makeCard(
                            id: "combined.sleepStress",
                            category: .combined,
                            sectionTitle: "Combined",
                            headline: "Low sleep + high stress associated with weaker results",
                            detail: "\(money(combined.expectancy ?? combined.averagePnL ?? 0)) expectancy (\(combined.tradeCount) trades) when both are present",
                            metrics: combined,
                            magnitude: delta,
                            actionability: 0.65
                        )
                    )
                }
            }
        }

        // High conviction + followed plan
        let disciplinedHighConviction = enriched.filter {
            ($0.trade.confidence ?? 0) >= 4 && $0.trade.followedPlan == true
        }
        if disciplinedHighConviction.count >= 10 {
            let m = metrics(for: disciplinedHighConviction.map(\.trade))
            let allHigh = enriched.filter { ($0.trade.confidence ?? 0) >= 4 }
            let allHighMetrics = metrics(for: allHigh.map(\.trade))
            if m.reliability.qualifiesForComparison,
               allHighMetrics.reliability.qualifiesForComparison,
               (m.expectancy ?? 0) > (allHighMetrics.expectancy ?? 0) + 5 {
                cards.append(
                    makeCard(
                        id: "combined.convictionPlan",
                        category: .combined,
                        sectionTitle: "Combined",
                        headline: "High conviction + plan followed is your strongest combo",
                        detail: "\(money(m.expectancy ?? m.averagePnL ?? 0)) expectancy • \(m.tradeCount) trades",
                        metrics: m,
                        magnitude: 10,
                        actionability: 0.7
                    )
                )
            }
        }

        return cards
    }

    // MARK: - Detail sections

    private static func buildSections(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics,
        allCandidates: [PsychologyInsightCard]
    ) -> [PsychologyAnalyticsSection] {
        var sections: [PsychologyAnalyticsSection] = []

        sections.append(
            PsychologyAnalyticsSection(
                id: "overview",
                title: "Overview",
                subtitle: "Based on \(baseline.tradeCount) trades in this period",
                groups: [
                    PsychologyAnalyticsGroupRow(
                        id: "baseline",
                        label: "All trades",
                        metrics: baseline,
                        highlight: false
                    ),
                ],
                footnote: baseline.reliability.label
            )
        )

        sections.append(sleepSection(enriched: enriched))
        sections.append(mentalStateSection(enriched: enriched))
        sections.append(convictionSection(enriched: enriched))
        sections.append(disciplineSection(enriched: enriched))
        sections.append(emotionSection(enriched: enriched))
        sections.append(afterLossesSection(enriched: enriched))
        sections.append(tradeFrequencySection(enriched: enriched))

        if allCandidates.contains(where: { $0.category == .combined }) {
            sections.append(
                PsychologyAnalyticsSection(
                    id: "combined",
                    title: "Combined Signals",
                    subtitle: "Conservative multi-factor patterns only",
                    groups: allCandidates
                        .filter { $0.category == .combined }
                        .map {
                            PsychologyAnalyticsGroupRow(
                                id: $0.id,
                                label: $0.headline,
                                metrics: PsychologyGroupMetrics(
                                    tradeCount: $0.sampleSize,
                                    winCount: 0,
                                    lossCount: 0,
                                    winRate: nil,
                                    totalPnL: 0,
                                    averagePnL: nil,
                                    expectancy: nil,
                                    averageRR: nil,
                                    profitFactor: nil,
                                    reliability: $0.reliability
                                ),
                                highlight: true
                            )
                        },
                    footnote: "Associated patterns — not proof of causation."
                )
            )
        }

        return sections
    }

    private static func sleepSection(enriched: [PsychologyEnrichedTrade]) -> PsychologyAnalyticsSection {
        let withSleep = enriched.filter { $0.dailyCheckIn?.sleepHours != nil }
        let grouped = Dictionary(grouping: withSleep) {
            SleepPerformanceBand.resolve($0.dailyCheckIn?.sleepHours) ?? .underFive
        }
        let rows = SleepPerformanceBand.allCases.compactMap { band -> PsychologyAnalyticsGroupRow? in
            guard let items = grouped[band] else { return nil }
            let m = metrics(for: items.map(\.trade))
            return PsychologyAnalyticsGroupRow(id: band.rawValue, label: band.rawValue, metrics: m, highlight: false)
        }
        return section(
            id: "sleep",
            title: "Sleep",
            subtitle: "Trades with a daily check-in that logged sleep hours",
            rows: rows,
            emptyMessage: "Log daily check-ins with sleep hours to unlock sleep analysis."
        )
    }

    private static func mentalStateSection(enriched: [PsychologyEnrichedTrade]) -> PsychologyAnalyticsSection {
        var rows: [PsychologyAnalyticsGroupRow] = []
        for dimension in DailyRatingDimension.allCases {
            for rating in 1...5 {
                let items = enriched.filter {
                    guard let checkIn = $0.dailyCheckIn,
                          let value = dimension.rating(from: checkIn)
                    else { return false }
                    return value == rating
                }
                guard !items.isEmpty else { continue }
                let m = metrics(for: items.map(\.trade))
                rows.append(
                    PsychologyAnalyticsGroupRow(
                        id: "\(dimension.rawValue).\(rating)",
                        label: "\(dimension.title) \(rating)/5",
                        metrics: m,
                        highlight: false
                    )
                )
            }
        }
        return section(
            id: "mentalState",
            title: "Mental State",
            subtitle: "Sleep quality, morning, stress, energy, and focus ratings",
            rows: rows,
            emptyMessage: "Complete daily check-ins to analyze mental-state patterns."
        )
    }

    private static func convictionSection(enriched: [PsychologyEnrichedTrade]) -> PsychologyAnalyticsSection {
        let rows = (1...5).compactMap { level -> PsychologyAnalyticsGroupRow? in
            let items = enriched.filter { $0.trade.confidence == level }
            guard !items.isEmpty else { return nil }
            return PsychologyAnalyticsGroupRow(
                id: "conviction.\(level)",
                label: "Conviction \(level)/5",
                metrics: metrics(for: items.map(\.trade)),
                highlight: false
            )
        }
        return section(
            id: "conviction",
            title: "Trade Psychology",
            subtitle: "Conviction at entry",
            rows: rows,
            emptyMessage: "Add conviction on more trades to unlock this section."
        )
    }

    private static func disciplineSection(enriched: [PsychologyEnrichedTrade]) -> PsychologyAnalyticsSection {
        let followed = enriched.filter { $0.trade.followedPlan == true }
        let notFollowed = enriched.filter { $0.trade.followedPlan == false }
        let unknown = enriched.filter { $0.trade.followedPlan == nil }
        var rows: [PsychologyAnalyticsGroupRow] = []
        if !followed.isEmpty {
            rows.append(PsychologyAnalyticsGroupRow(id: "plan.yes", label: "Followed plan", metrics: metrics(for: followed.map(\.trade)), highlight: false))
        }
        if !notFollowed.isEmpty {
            rows.append(PsychologyAnalyticsGroupRow(id: "plan.no", label: "Did not follow plan", metrics: metrics(for: notFollowed.map(\.trade)), highlight: false))
        }
        if !unknown.isEmpty {
            rows.append(PsychologyAnalyticsGroupRow(id: "plan.unknown", label: "Not recorded", metrics: metrics(for: unknown.map(\.trade)), highlight: false))
        }
        return section(id: "discipline", title: "Discipline", subtitle: "Plan adherence", rows: rows, emptyMessage: "Mark plan adherence on trades to compare discipline.")
    }

    private static func emotionSection(enriched: [PsychologyEnrichedTrade]) -> PsychologyAnalyticsSection {
        let grouped = Dictionary(grouping: enriched.compactMap { item -> (PsychologyEnrichedTrade, String)? in
            guard let emotion = normalizedEmotion(item.trade.emotion) else { return nil }
            return (item, emotion)
        }, by: \.1)
        let rows = TradeReviewCatalog.emotions.compactMap { emotion -> PsychologyAnalyticsGroupRow? in
            guard let items = grouped[emotion] else { return nil }
            return PsychologyAnalyticsGroupRow(
                id: "emotion.\(emotion)",
                label: emotion,
                metrics: metrics(for: items.map(\.0.trade)),
                highlight: false
            )
        }
        return section(id: "emotion", title: "Emotion", subtitle: "Emotion before entry", rows: rows, emptyMessage: "Tag emotions on trades to analyze emotional patterns.")
    }

    private static func afterLossesSection(enriched: [PsychologyEnrichedTrade]) -> PsychologyAnalyticsSection {
        let grouped = Dictionary(grouping: enriched) {
            ConsecutiveLossBucket.resolve($0.consecutiveLossesBefore)
        }
        let rows = ConsecutiveLossBucket.allCases.compactMap { bucket -> PsychologyAnalyticsGroupRow? in
            guard let items = grouped[bucket] else { return nil }
            return PsychologyAnalyticsGroupRow(
                id: bucket.rawValue,
                label: bucket.rawValue,
                metrics: metrics(for: items.map(\.trade)),
                highlight: false
            )
        }
        return section(id: "afterLosses", title: "After Losses", subtitle: "Performance by consecutive losses before entry", rows: rows, emptyMessage: nil)
    }

    private static func tradeFrequencySection(enriched: [PsychologyEnrichedTrade]) -> PsychologyAnalyticsSection {
        let grouped = Dictionary(grouping: enriched) {
            TradeSequenceBucket.resolve($0.tradeNumberInDay)
        }
        let rows = TradeSequenceBucket.allCases.compactMap { bucket -> PsychologyAnalyticsGroupRow? in
            guard let items = grouped[bucket] else { return nil }
            return PsychologyAnalyticsGroupRow(
                id: bucket.rawValue,
                label: bucket.rawValue,
                metrics: metrics(for: items.map(\.trade)),
                highlight: false
            )
        }
        return section(id: "tradeFrequency", title: "Trade Frequency", subtitle: "Trade sequence within each trading day", rows: rows, emptyMessage: nil)
    }

    private static func section(
        id: String,
        title: String,
        subtitle: String?,
        rows: [PsychologyAnalyticsGroupRow],
        emptyMessage: String?
    ) -> PsychologyAnalyticsSection {
        PsychologyAnalyticsSection(
            id: id,
            title: title,
            subtitle: subtitle,
            groups: rows,
            footnote: rows.isEmpty ? emptyMessage : nil
        )
    }

    // MARK: - Ranking

    static func rankInsights(_ candidates: [PsychologyInsightCard]) -> [PsychologyInsightCard] {
        candidates
            .filter { $0.reliability.qualifiesForDashboardCard }
            .sorted { $0.rankingScore > $1.rankingScore }
    }

    private static func makeCard(
        id: String,
        category: PsychologyInsightCategory,
        sectionTitle: String,
        headline: String,
        detail: String,
        metrics: PsychologyGroupMetrics,
        magnitude: Double,
        actionability: Double
    ) -> PsychologyInsightCard {
        let reliabilityWeight: Double = {
            switch metrics.reliability {
            case .insufficient: return 0
            case .earlySignal: return 0.35
            case .developing: return 0.75
            case .strong: return 1.0
            }
        }()
        let sampleWeight = min(1.0, Double(metrics.tradeCount) / 30.0)
        let magnitudeWeight = min(1.0, magnitude / 50.0)
        let score = reliabilityWeight * sampleWeight * magnitudeWeight * actionability

        return PsychologyInsightCard(
            id: id,
            category: category,
            sectionTitle: sectionTitle,
            headline: headline,
            detail: detail,
            sampleSize: metrics.tradeCount,
            reliability: metrics.reliability,
            rankingScore: score
        )
    }

    // MARK: - Helpers

    private enum PnLSign { case win, loss, flat }

    private static func pnlSign(_ trade: Trade) -> PnLSign {
        let pnl = trade.realizedPnL?.amount ?? 0
        if pnl > 0 { return .win }
        if pnl < 0 { return .loss }
        return .flat
    }

    private static func normalizedEmotion(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return TradeReviewCatalog.emotions.first {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        } ?? trimmed
    }

    static func formatWinRate(_ rate: Decimal?) -> String {
        guard let rate else { return "—" }
        let pct = NSDecimalNumber(decimal: rate * 100).doubleValue
        return String(format: "%.0f%%", pct)
    }

    static func money(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "$0"
    }
}
