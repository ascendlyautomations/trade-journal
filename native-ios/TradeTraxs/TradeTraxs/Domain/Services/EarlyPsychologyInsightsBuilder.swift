import Foundation

/// Daily check-in ↔ trade joins with small-sample insight cards (web `dailyPsychologyInsights.ts` parity).
nonisolated enum EarlyPsychologyInsightsBuilder {
    struct MatchedTradingDay: Hashable, Sendable {
        var dateKey: String
        var checkIn: TraderDailyCheckIn
        var dailyPnL: Decimal
        var tradeCount: Int
        var winCount: Int
        var lossCount: Int
        var winRate: Decimal?
    }

    struct DailyGroupAggregate: Hashable, Sendable {
        var label: String
        var dayCount: Int
        var tradeCount: Int
        var totalPnL: Decimal
        var avgDailyPnL: Decimal
        var winRate: Decimal?
        var reliability: PsychologySampleReliability
    }

    static func buildMatchedTradingDays(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [MatchedTradingDay] {
        let complete = checkIns.filter(\.isComplete)
        let byDate = Dictionary(uniqueKeysWithValues: complete.map { ($0.checkInDate, $0) })
        var buckets: [String: (checkIn: TraderDailyCheckIn, pnls: [Decimal])] = [:]

        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            guard let checkIn = byDate[key] else { continue }
            let pnl = trade.realizedPnL?.amount ?? 0
            var bucket = buckets[key] ?? (checkIn, [])
            bucket.pnls.append(pnl)
            buckets[key] = bucket
        }

        return buckets.keys.sorted().compactMap { key -> MatchedTradingDay? in
            guard let bucket = buckets[key] else { return nil }
            let pnls = bucket.pnls
            let winCount = pnls.filter { $0 > 0 }.count
            let lossCount = pnls.filter { $0 < 0 }.count
            let tradeCount = pnls.count
            let total = pnls.reduce(0, +)
            let winRate: Decimal? = tradeCount > 0
                ? Decimal(winCount) / Decimal(tradeCount)
                : nil
            return MatchedTradingDay(
                dateKey: key,
                checkIn: bucket.checkIn,
                dailyPnL: total,
                tradeCount: tradeCount,
                winCount: winCount,
                lossCount: lossCount,
                winRate: winRate
            )
        }
    }

    static func resolveMatchedDayReliability(dayCount: Int, tradeCount: Int) -> PsychologySampleReliability {
        guard dayCount >= 1, tradeCount >= 1 else { return .insufficient }
        if dayCount == 1, tradeCount < 5 { return .earlySignal }
        if dayCount <= 4 { return .earlySignal }
        if dayCount <= 9 { return .developing }
        return .strong
    }

    static func build(trades: [Trade], checkIns: [TraderDailyCheckIn]) -> [PsychologyInsightCard] {
        let days = buildMatchedTradingDays(trades: trades, checkIns: checkIns)
        var cards: [PsychologyInsightCard] = []

        if let overview = overviewCard(days: days) {
            cards.append(overview)
        }
        cards.append(contentsOf: ratingDimensionCards(days: days))
        cards.append(contentsOf: tradeTagCards(trades: trades))

        var seen = Set<String>()
        let unique = cards.filter { card in
            guard !seen.contains(card.id) else { return false }
            seen.insert(card.id)
            return true
        }
        return Array(unique.sorted { $0.rankingScore > $1.rankingScore }.prefix(8))
    }

    static func merge(
        early: [PsychologyInsightCard],
        reportCards: [PsychologyInsightCard]
    ) -> [PsychologyInsightCard] {
        guard !reportCards.isEmpty else { return Array(early.prefix(8)) }
        let ids = Set(reportCards.map(\.id))
        let extras = early.filter { !ids.contains($0.id) }
        return Array((reportCards + extras).prefix(8))
    }

    static func hasMatchedData(trades: [Trade], checkIns: [TraderDailyCheckIn]) -> Bool {
        !buildMatchedTradingDays(trades: trades, checkIns: checkIns).isEmpty
    }

    // MARK: - Private

    private static func aggregate(label: String, days: [MatchedTradingDay]) -> DailyGroupAggregate {
        let tradeCount = days.reduce(0) { $0 + $1.tradeCount }
        let winCount = days.reduce(0) { $0 + $1.winCount }
        let totalPnL = days.reduce(0) { $0 + $1.dailyPnL }
        let dayCount = days.count
        let winRate: Decimal? = tradeCount > 0 ? Decimal(winCount) / Decimal(tradeCount) : nil
        return DailyGroupAggregate(
            label: label,
            dayCount: dayCount,
            tradeCount: tradeCount,
            totalPnL: totalPnL,
            avgDailyPnL: dayCount > 0 ? totalPnL / Decimal(dayCount) : 0,
            winRate: winRate,
            reliability: resolveMatchedDayReliability(dayCount: dayCount, tradeCount: tradeCount)
        )
    }

    private static func reliabilityNote(_ reliability: PsychologySampleReliability) -> String {
        switch reliability {
        case .earlySignal: return "Early observation, small sample"
        case .developing: return "Developing pattern"
        case .strong: return "Stronger sample"
        case .insufficient: return "Limited data"
        }
    }

    private static func formatGroupDetail(_ group: DailyGroupAggregate) -> String {
        var parts = [
            "\(group.dayCount) trading \(group.dayCount == 1 ? "day" : "days")",
            "\(TraderPsychologyAnalyticsEngine.money(group.totalPnL)) total P&L",
            "\(TraderPsychologyAnalyticsEngine.money(group.avgDailyPnL)) avg / day",
        ]
        if let winRate = group.winRate {
            parts.append("\(TraderPsychologyAnalyticsEngine.formatWinRate(winRate)) win rate")
        }
        parts.append("\(group.tradeCount) trades")
        parts.append(reliabilityNote(group.reliability))
        return parts.joined(separator: " · ")
    }

    private static func overviewCard(days: [MatchedTradingDay]) -> PsychologyInsightCard? {
        guard !days.isEmpty else { return nil }
        let group = aggregate(label: "Matched check-in days", days: days)
        return PsychologyInsightCard(
            id: "matchedDays.overview",
            category: .combined,
            sectionTitle: "Matched days",
            headline: "\(group.dayCount) trading \(group.dayCount == 1 ? "day" : "days") with check-ins",
            detail: formatGroupDetail(group),
            sampleSize: group.tradeCount,
            reliability: group.reliability,
            rankingScore: 1.0
        )
    }

    private static func ratingSplitCards(
        id: String,
        sectionTitle: String,
        category: PsychologyInsightCategory,
        days: [MatchedTradingDay],
        goodLabel: String,
        poorLabel: String,
        read: (MatchedTradingDay) -> Int?,
        goodWhen: (Int) -> Bool,
        poorWhen: (Int) -> Bool
    ) -> [PsychologyInsightCard] {
        let goodDays = days.filter { day in
            guard let r = read(day) else { return false }
            return goodWhen(r)
        }
        let poorDays = days.filter { day in
            guard let r = read(day) else { return false }
            return poorWhen(r)
        }

        if !goodDays.isEmpty, !poorDays.isEmpty {
            let good = aggregate(label: goodLabel, days: goodDays)
            let poor = aggregate(label: poorLabel, days: poorDays)
            let goodBetter = good.avgDailyPnL >= poor.avgDailyPnL
            let (better, worse, bLabel, wLabel) = goodBetter
                ? (good, poor, goodLabel, poorLabel)
                : (poor, good, poorLabel, goodLabel)
            let detail =
                "\(bLabel): \(TraderPsychologyAnalyticsEngine.money(better.avgDailyPnL))/day (\(better.dayCount)d) vs " +
                "\(wLabel): \(TraderPsychologyAnalyticsEngine.money(worse.avgDailyPnL))/day (\(worse.dayCount)d) · " +
                "\(better.tradeCount + worse.tradeCount) trades · " +
                "\(reliabilityNote(resolveMatchedDayReliability(dayCount: better.dayCount + worse.dayCount, tradeCount: better.tradeCount + worse.tradeCount))), association only, not causation"
            return [
                PsychologyInsightCard(
                    id: "\(id).compare",
                    category: category,
                    sectionTitle: sectionTitle,
                    headline: "\(bLabel) vs \(wLabel) (daily P&L)",
                    detail: detail,
                    sampleSize: better.tradeCount + worse.tradeCount,
                    reliability: resolveMatchedDayReliability(
                        dayCount: better.dayCount + worse.dayCount,
                        tradeCount: better.tradeCount + worse.tradeCount
                    ),
                    rankingScore: 0.7
                ),
            ]
        }

        var cards: [PsychologyInsightCard] = []
        if !goodDays.isEmpty {
            let g = aggregate(label: goodLabel, days: goodDays)
            cards.append(
                PsychologyInsightCard(
                    id: "\(id).good",
                    category: category,
                    sectionTitle: sectionTitle,
                    headline: "\(goodLabel) days in your sample",
                    detail: formatGroupDetail(g),
                    sampleSize: g.tradeCount,
                    reliability: g.reliability,
                    rankingScore: 0.45
                )
            )
        }
        if !poorDays.isEmpty {
            let p = aggregate(label: poorLabel, days: poorDays)
            cards.append(
                PsychologyInsightCard(
                    id: "\(id).poor",
                    category: category,
                    sectionTitle: sectionTitle,
                    headline: "\(poorLabel) days in your sample",
                    detail: formatGroupDetail(p),
                    sampleSize: p.tradeCount,
                    reliability: p.reliability,
                    rankingScore: 0.4
                )
            )
        }
        return cards
    }

    private static func ratingDimensionCards(days: [MatchedTradingDay]) -> [PsychologyInsightCard] {
        guard !days.isEmpty else { return [] }
        var cards: [PsychologyInsightCard] = []
        cards.append(
            contentsOf: ratingSplitCards(
                id: "sleepQuality",
                sectionTitle: "Sleep",
                category: .sleep,
                days: days,
                goodLabel: "Good sleep (4–5)",
                poorLabel: "Poor sleep (1–2)",
                read: { $0.checkIn.sleepQuality },
                goodWhen: { $0 >= 4 },
                poorWhen: { $0 <= 2 }
            )
        )
        cards.append(
            contentsOf: ratingSplitCards(
                id: "focus",
                sectionTitle: "Focus",
                category: .mentalState,
                days: days,
                goodLabel: "Focused (4–5)",
                poorLabel: "Unfocused (1–2)",
                read: { $0.checkIn.focusLevel },
                goodWhen: { $0 >= 4 },
                poorWhen: { $0 <= 2 }
            )
        )
        cards.append(
            contentsOf: ratingSplitCards(
                id: "morning",
                sectionTitle: "Morning mood",
                category: .mentalState,
                days: days,
                goodLabel: "Positive morning (4–5)",
                poorLabel: "Low morning (1–2)",
                read: { $0.checkIn.morningRating },
                goodWhen: { $0 >= 4 },
                poorWhen: { $0 <= 2 }
            )
        )
        cards.append(
            contentsOf: ratingSplitCards(
                id: "stress",
                sectionTitle: "Stress",
                category: .mentalState,
                days: days,
                goodLabel: "Low stress (1–2)",
                poorLabel: "High stress (4–5)",
                read: { $0.checkIn.stressLevel },
                goodWhen: { $0 <= 2 },
                poorWhen: { $0 >= 4 }
            )
        )
        cards.append(
            contentsOf: ratingSplitCards(
                id: "energy",
                sectionTitle: "Energy",
                category: .mentalState,
                days: days,
                goodLabel: "High energy (4–5)",
                poorLabel: "Low energy (1–2)",
                read: { $0.checkIn.energyLevel },
                goodWhen: { $0 >= 4 },
                poorWhen: { $0 <= 2 }
            )
        )
        return cards
    }

    private static func tradeTagCards(trades: [Trade]) -> [PsychologyInsightCard] {
        var cards: [PsychologyInsightCard] = []
        let highConf = trades.filter { ($0.confidence ?? 0) >= 4 }
        let lowConf = trades.filter { let c = $0.confidence ?? 0; return c >= 1 && c <= 2 }

        if !highConf.isEmpty, !lowConf.isEmpty {
            let hi = TraderPsychologyAnalyticsEngine.metrics(for: highConf)
            let lo = TraderPsychologyAnalyticsEngine.metrics(for: lowConf)
            cards.append(
                PsychologyInsightCard(
                    id: "trade.confidence.compare",
                    category: .conviction,
                    sectionTitle: "Confidence",
                    headline: "High vs low confidence trades",
                    detail:
                        "4–5: \(TraderPsychologyAnalyticsEngine.money(hi.averagePnL ?? 0)) avg (\(hi.tradeCount) trades) vs " +
                        "1–2: \(TraderPsychologyAnalyticsEngine.money(lo.averagePnL ?? 0)) avg (\(lo.tradeCount) trades) · " +
                        reliabilityNote(resolveMatchedDayReliability(dayCount: 0, tradeCount: hi.tradeCount + lo.tradeCount)),
                    sampleSize: hi.tradeCount + lo.tradeCount,
                    reliability: resolveMatchedDayReliability(dayCount: 0, tradeCount: hi.tradeCount + lo.tradeCount),
                    rankingScore: 0.65
                )
            )
        } else if !highConf.isEmpty {
            let hi = TraderPsychologyAnalyticsEngine.metrics(for: highConf)
            cards.append(
                PsychologyInsightCard(
                    id: "trade.confidence.high",
                    category: .conviction,
                    sectionTitle: "Confidence",
                    headline: "High-confidence trades (4–5)",
                    detail:
                        "\(TraderPsychologyAnalyticsEngine.money(hi.totalPnL)) total · " +
                        "\(TraderPsychologyAnalyticsEngine.formatWinRate(hi.winRate)) win rate · " +
                        "\(hi.tradeCount) trades · " +
                        reliabilityNote(resolveMatchedDayReliability(dayCount: 0, tradeCount: hi.tradeCount)),
                    sampleSize: hi.tradeCount,
                    reliability: resolveMatchedDayReliability(dayCount: 0, tradeCount: hi.tradeCount),
                    rankingScore: 0.5
                )
            )
        }

        let followed = trades.filter { $0.followedPlan == true }
        let broken = trades.filter { $0.followedPlan == false }
        if !followed.isEmpty, !broken.isEmpty {
            let f = TraderPsychologyAnalyticsEngine.metrics(for: followed)
            let b = TraderPsychologyAnalyticsEngine.metrics(for: broken)
            cards.append(
                PsychologyInsightCard(
                    id: "trade.plan.compare",
                    category: .discipline,
                    sectionTitle: "Discipline",
                    headline: "Plan followed vs not followed",
                    detail:
                        "Followed: \(TraderPsychologyAnalyticsEngine.money(f.averagePnL ?? 0)) avg (\(f.tradeCount)) vs " +
                        "not: \(TraderPsychologyAnalyticsEngine.money(b.averagePnL ?? 0)) avg (\(b.tradeCount)) · " +
                        reliabilityNote(resolveMatchedDayReliability(dayCount: 0, tradeCount: f.tradeCount + b.tradeCount)),
                    sampleSize: f.tradeCount + b.tradeCount,
                    reliability: resolveMatchedDayReliability(dayCount: 0, tradeCount: f.tradeCount + b.tradeCount),
                    rankingScore: 0.75
                )
            )
        }

        return cards
    }
}
