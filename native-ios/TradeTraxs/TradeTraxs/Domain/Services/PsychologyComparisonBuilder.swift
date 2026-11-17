import Foundation

/// Shared psychology comparisons for insights, advanced rows, and guardrails.
/// Mirrors `lib/psychology/reports/comparisons.ts`.
nonisolated enum PsychologyComparisonBuilder {
    static let insightMinimumTrades = 8
    static let advancedMinimumTrades = 5
    static let minimumWinRateGap = 0.08
    static let minimumAveragePnLGap = 15.0
    static let pnlGapRatio = 0.25
    static let earlyMaximumTrades = 19
    static let insightLimit = 3

    private static let strainedEmotions: Set<String> = [
        "Fearful", "FOMO", "Frustrated", "Hesitant", "Overconfident",
    ]

    struct Result: Sendable {
        var insights: [PsychologyInsightCard]
        var sections: [PsychologyAnalyticsSection]
        var guardrails: PsychologyCoachGuardrailFacts
    }

    static func build(
        enriched: [PsychologyEnrichedTrade],
        preferences: PreferenceRuleContext? = nil
    ) -> Result {
        let comparisons = collect(enriched, preferences: preferences)
        let insights = comparisons
            .filter { minCount($0) >= insightMinimumTrades }
            .sorted { card(for: $0).rankingScore > card(for: $1).rankingScore }
            .prefix(insightLimit)
            .map(card(for:))
        let sections = comparisons
            .sorted { $0.rank < $1.rank }
            .map(section(for:))
        return Result(
            insights: Array(insights),
            sections: sections,
            guardrails: guardrails(from: comparisons, preferences: preferences, enriched: enriched)
        )
    }

    static func matchedDayCount(trades: [Trade], checkIns: [TraderDailyCheckIn]) -> Int {
        let complete = Set(checkIns.filter(\.isComplete).map(\.checkInDate))
        var matched = Set<String>()
        for trade in trades {
            let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
            if complete.contains(key) {
                matched.insert(key)
            }
        }
        return matched.count
    }

    // MARK: - Comparison model

    private struct Side {
        var label: String
        var sampleLabel: String
        var metrics: PsychologyGroupMetrics
    }

    private struct CopyPair {
        var headline: String
        var suggestion: String
    }

    private struct Resolved {
        var id: String
        var category: PsychologyInsightCategory
        var title: String
        var left: Side
        var right: Side
        var favorable: String
        var rank: Int
        var leader: String
        var byWinRateOnly: Bool
        var winRateGap: Double
        var averagePnLGap: Double?
        var headline: String
        var suggestion: String
        var sampleLine: String
        var early: Bool
    }

    private struct Draft {
        var id: String
        var category: PsychologyInsightCategory
        var title: String
        var left: Side
        var right: Side
        var rank: Int
        var whenLeftLeads: (pnl: CopyPair, winRate: CopyPair)
        var whenRightLeads: (pnl: CopyPair, winRate: CopyPair)
    }

    private static func collect(
        _ enriched: [PsychologyEnrichedTrade],
        preferences: PreferenceRuleContext?
    ) -> [Resolved] {
        var drafts: [Draft] = []

        let shortSleep = enriched.filter { (hours($0) ?? 99) < 6 && hours($0) != nil }
        let rested = enriched.filter { (hours($0) ?? -1) >= 7 }
        drafts.append(Draft(
            id: "sleep",
            category: .sleep,
            title: "Sleep",
            left: side("7h or more", "better-rested", rested),
            right: side("Under 6h", "short-sleep", shortSleep),
            rank: 20,
            whenLeftLeads: (
                CopyPair(headline: "You've performed better when you slept at least 7 hours.", suggestion: "Protecting sleep before the session may be worth prioritizing."),
                CopyPair(headline: "You've won more often when you slept at least 7 hours.", suggestion: "Protecting sleep before the session may be worth prioritizing.")
            ),
            whenRightLeads: (
                CopyPair(headline: "Shorter sleep has lined up with better results in this sample.", suggestion: "Sleep has not been the limiter in these trades."),
                CopyPair(headline: "Shorter sleep has lined up with more wins in this sample.", suggestion: "Sleep has not been the limiter in these trades.")
            )
        ))

        let ratings: [(String, String, (PsychologyEnrichedTrade) -> Int?, String, String, String, String, String, String, Int)] = [
            ("focus", "Focus", { $0.dailyCheckIn?.focusLevel }, "higher-focus", "lower-focus", "Focus 4–5", "Focus 1–2", "higher-focus", "lower-focus", 30),
            ("energy", "Energy", { $0.dailyCheckIn?.energyLevel }, "higher-energy", "lower-energy", "Energy 4–5", "Energy 1–2", "higher-energy", "lower-energy", 40),
            ("morning", "Morning", { $0.dailyCheckIn?.morningRating }, "stronger-morning", "low-morning", "Morning 4–5", "Morning 1–2", "stronger-morning", "low-morning", 50),
            ("sleepQuality", "Sleep quality", { $0.dailyCheckIn?.sleepQuality }, "better sleep-quality", "poor sleep-quality", "Sleep quality 4–5", "Sleep quality 1–2", "better sleep-quality", "poor sleep-quality", 25),
        ]
        for spec in ratings {
            let bands = bandRows(enriched, read: spec.2, high: { $0 >= 4 }, low: { $0 <= 2 })
            let copy = ratingCopy(favorable: spec.3, weaker: spec.4)
            drafts.append(Draft(
                id: spec.0,
                category: .mentalState,
                title: spec.1,
                left: side(spec.5, spec.7, bands.high),
                right: side(spec.6, spec.8, bands.low),
                rank: spec.9,
                whenLeftLeads: copy.left,
                whenRightLeads: copy.right
            ))
        }

        let stress = bandRows(enriched, read: { $0.dailyCheckIn?.stressLevel }, high: { $0 <= 2 }, low: { $0 >= 4 })
        drafts.append(Draft(
            id: "stress",
            category: .mentalState,
            title: "Stress",
            left: side("Stress 1–2", "lower-stress", stress.high),
            right: side("Stress 4–5", "higher-stress", stress.low),
            rank: 15,
            whenLeftLeads: (
                CopyPair(headline: "You've performed better on lower-stress days.", suggestion: "A short reset when stress is high may help."),
                CopyPair(headline: "You've won more often on lower-stress days.", suggestion: "A short reset when stress is high may help.")
            ),
            whenRightLeads: (
                CopyPair(headline: "Higher-stress days have performed better in this sample.", suggestion: "Stress has not lined up with weaker results here."),
                CopyPair(headline: "Higher-stress days have won more often in this sample.", suggestion: "Stress has not lined up with weaker results here.")
            )
        ))

        let highConviction = enriched.filter { ($0.trade.confidence ?? 0) >= 4 }
        let lowConviction = enriched.filter {
            guard let confidence = $0.trade.confidence else { return false }
            return (1...2).contains(confidence)
        }
        drafts.append(Draft(
            id: "conviction",
            category: .conviction,
            title: "Conviction",
            left: side("Conviction 4–5", "higher-conviction", highConviction),
            right: side("Conviction 1–2", "lower-conviction", lowConviction),
            rank: 10,
            whenLeftLeads: (
                CopyPair(headline: "Your higher-conviction trades have performed better.", suggestion: "Being more selective when confidence is low may help."),
                CopyPair(headline: "Your higher-conviction trades have won more often.", suggestion: "Being more selective when confidence is low may help.")
            ),
            whenRightLeads: (
                CopyPair(headline: "Your lower-conviction trades have performed better in this sample.", suggestion: "High confidence has not lined up with better results, so it may be worth reviewing what conviction means before you size up."),
                CopyPair(headline: "Your lower-conviction trades have won more often in this sample.", suggestion: "High confidence has not lined up with more wins, so it may be worth reviewing what conviction means before you size up.")
            )
        ))

        drafts.append(Draft(
            id: "discipline",
            category: .discipline,
            title: "Plan",
            left: side("Followed plan", "plan-followed", enriched.filter { $0.trade.followedPlan == true }),
            right: side("Off plan", "off-plan", enriched.filter { $0.trade.followedPlan == false }),
            rank: 12,
            whenLeftLeads: (
                CopyPair(headline: "Trades where you followed your plan have performed better.", suggestion: "Staying with the plan looks like part of your edge."),
                CopyPair(headline: "Trades where you followed your plan have won more often.", suggestion: "Staying with the plan looks like part of your edge.")
            ),
            whenRightLeads: (
                CopyPair(headline: "Trades marked off your plan have performed better in this sample.", suggestion: "Review those trades before treating a plan break as the main problem."),
                CopyPair(headline: "Trades marked off your plan have won more often in this sample.", suggestion: "Review those trades before treating a plan break as the main problem.")
            )
        ))

        if let emotion = emotionDraft(enriched) {
            drafts.append(emotion)
        }

        let pauses = enriched.compactMap {
            PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).consecutiveLossPause
        }
        let personalPause = !pauses.isEmpty
        let uniquePause = Set(pauses).count == 1 ? pauses.first : nil
        let baseline = personalPause
            ? enriched.filter {
                PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).consecutiveLossPause != nil
                    && $0.consecutiveLossesBefore == 0
            }
            : enriched.filter { $0.consecutiveLossesBefore == 0 }
        let after = personalPause
            ? enriched.filter {
                guard let pause = PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).consecutiveLossPause else {
                    return false
                }
                return $0.consecutiveLossesBefore >= pause
            }
            : enriched.filter { $0.consecutiveLossesBefore >= 2 }
        let afterLabel = personalPause
            ? (uniquePause.map { "After \($0)+ losses" } ?? "After your pause")
            : "After 2+ losses"
        drafts.append(Draft(
            id: "afterLosses",
            category: .afterLosses,
            title: "After losses",
            left: side("No prior loss", "baseline", baseline),
            right: side(afterLabel, "post-streak", after),
            rank: 8,
            whenLeftLeads: (
                CopyPair(
                    headline: personalPause
                        ? "Trades taken after your consecutive-loss pause have tended to perform worse."
                        : "Trades taken after a losing streak have tended to perform worse.",
                    suggestion: personalPause
                        ? "That is a result difference after your saved pause. It does not explain why the trade was taken."
                        : "Taking a break after consecutive losses may help."
                ),
                CopyPair(
                    headline: personalPause
                        ? "Trades taken after your consecutive-loss pause have won less often."
                        : "Trades taken after a losing streak have won less often.",
                    suggestion: personalPause
                        ? "That is a result difference after your saved pause. It does not explain why the trade was taken."
                        : "Taking a break after consecutive losses may help."
                )
            ),
            whenRightLeads: (
                CopyPair(
                    headline: personalPause
                        ? "Trades after your consecutive-loss pause have held up in this sample."
                        : "Trades after a losing streak have held up in this sample.",
                    suggestion: "A forced pause is not supported by these results."
                ),
                CopyPair(
                    headline: personalPause
                        ? "Trades after your consecutive-loss pause have won more often in this sample."
                        : "Trades after a losing streak have won more often in this sample.",
                    suggestion: "A forced pause is not supported by these results."
                )
            )
        ))

        let caps = enriched.compactMap {
            PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).maxTradesPerDay
        }
        let personalCap = !caps.isEmpty
        let uniqueCap = Set(caps).count == 1 ? caps.first : nil
        let early = personalCap
            ? enriched.filter {
                guard let cap = PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).maxTradesPerDay else {
                    return false
                }
                return $0.tradeNumberInDay <= cap
            }
            : enriched.filter { (1...3).contains($0.tradeNumberInDay) }
        let late = personalCap
            ? enriched.filter {
                guard let cap = PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).maxTradesPerDay else {
                    return false
                }
                return $0.tradeNumberInDay > cap
            }
            : enriched.filter { $0.tradeNumberInDay >= 5 }
        drafts.append(Draft(
            id: "tradeFrequency",
            category: .tradeFrequency,
            title: "Trade sequence",
            left: side(personalCap ? (uniqueCap.map { "Within \($0) trades" } ?? "Within your daily cap") : "Trades 1–3", "earlier", early),
            right: side(personalCap ? (uniqueCap.map { "Beyond \($0) trades" } ?? "Beyond your daily cap") : "Trade 5+", "later", late),
            rank: 18,
            whenLeftLeads: (
                CopyPair(
                    headline: personalCap
                        ? "Trades beyond your daily cap have performed worse than trades within it."
                        : "Your earlier trades in the day have performed better than later ones.",
                    suggestion: personalCap
                        ? "This is your saved trade cap, not a guess about why the extra trades were taken."
                        : "Reviewing whether later setups are lower quality may help."
                ),
                CopyPair(
                    headline: personalCap
                        ? "Trades beyond your daily cap have won less often than trades within it."
                        : "Your earlier trades in the day have won more often than later ones.",
                    suggestion: personalCap
                        ? "This is your saved trade cap, not a guess about why the extra trades were taken."
                        : "Reviewing whether later setups are lower quality may help."
                )
            ),
            whenRightLeads: (
                CopyPair(
                    headline: personalCap
                        ? "Trades beyond your daily cap have performed better than trades within it in this sample."
                        : "Later trades in the day have performed better than your first few.",
                    suggestion: personalCap
                        ? "The cap is not pointing to weaker results right now."
                        : "The open has not been your strongest window in this sample."
                ),
                CopyPair(
                    headline: personalCap
                        ? "Trades beyond your daily cap have won more often than trades within it in this sample."
                        : "Later trades in the day have won more often than your first few.",
                    suggestion: personalCap
                        ? "The cap is not pointing to weaker results right now."
                        : "The open has not been your strongest window in this sample."
                )
            )
        ))

        let hasWait = enriched.contains {
            PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).waitAfterLossMinutes != nil
        }
        if hasWait {
            var rushed: [PsychologyEnrichedTrade] = []
            var waited: [PsychologyEnrichedTrade] = []
            let ordered = enriched.sorted { $0.trade.entryAt < $1.trade.entryAt }
            for index in ordered.indices.dropFirst() {
                let row = ordered[index]
                guard let wait = PreferenceComplianceEngine.psychologyRules(in: preferences, at: row.trade.entryAt).waitAfterLossMinutes,
                      row.previousTradeWasLoss
                else { continue }
                let minutes = row.trade.entryAt.timeIntervalSince(ordered[index - 1].trade.entryAt) / 60
                guard minutes >= 0 else { continue }
                if minutes < Double(wait) { rushed.append(row) } else { waited.append(row) }
            }
            drafts.append(Draft(
                id: "afterLossesWait",
                category: .afterLosses,
                title: "Wait after a loss",
                left: side("Waited", "waited", waited),
                right: side("Before the wait", "rushed", rushed),
                rank: 9,
                whenLeftLeads: (
                    CopyPair(
                        headline: "Trades taken before your waiting time after a loss have performed worse than trades that waited.",
                        suggestion: "This compares results against your saved wait. It does not label those trades."
                    ),
                    CopyPair(
                        headline: "Trades taken before your waiting time after a loss have won less often than trades that waited.",
                        suggestion: "This compares results against your saved wait. It does not label those trades."
                    )
                ),
                whenRightLeads: (
                    CopyPair(
                        headline: "Trades taken before your waiting time have held up in this sample.",
                        suggestion: "The saved wait is not pointing to weaker results right now."
                    ),
                    CopyPair(
                        headline: "Trades taken before your waiting time have won more often in this sample.",
                        suggestion: "The saved wait is not pointing to weaker results right now."
                    )
                )
            ))
        }

        return drafts.compactMap(resolve)
    }

    private static func emotionDraft(_ enriched: [PsychologyEnrichedTrade]) -> Draft? {
        var grouped: [String: [PsychologyEnrichedTrade]] = [:]
        for row in enriched {
            guard let emotion = normalizedEmotion(row.trade.emotion) else { continue }
            grouped[emotion, default: []].append(row)
        }
        let sides = grouped.map { emotion, rows in
            (emotion: emotion, rows: rows, metrics: TraderPsychologyAnalyticsEngine.metrics(for: rows.map(\.trade)))
        }
        .filter { $0.metrics.tradeCount >= advancedMinimumTrades }
        .sorted { lhs, rhs in
            switch (doubleValue(lhs.metrics.averagePnL), doubleValue(rhs.metrics.averagePnL)) {
            case (nil, nil):
                return (doubleValue(lhs.metrics.winRate) ?? 0) > (doubleValue(rhs.metrics.winRate) ?? 0)
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case let (left?, right?):
                if left != right { return left > right }
                return (doubleValue(lhs.metrics.winRate) ?? 0) > (doubleValue(rhs.metrics.winRate) ?? 0)
            }
        }
        guard sides.count >= 2, let best = sides.first, let worst = sides.last else { return nil }
        let suggestion = strainedEmotions.contains(worst.emotion)
            ? "Noticing \(worst.emotion) before you enter may be a useful pause."
            : "That tag has not lined up with weaker results here."
        return Draft(
            id: "emotion",
            category: .emotion,
            title: "Emotion",
            left: side(best.emotion, best.emotion, best.rows),
            right: side(worst.emotion, worst.emotion, worst.rows),
            rank: 35,
            whenLeftLeads: (
                CopyPair(headline: "Trades tagged \(best.emotion) have performed better than trades tagged \(worst.emotion).", suggestion: suggestion),
                CopyPair(headline: "Trades tagged \(best.emotion) have won more often than trades tagged \(worst.emotion).", suggestion: suggestion)
            ),
            whenRightLeads: (
                CopyPair(headline: "Trades tagged \(worst.emotion) have performed better than trades tagged \(best.emotion) in this sample.", suggestion: "The tag alone is not pointing to a weakness right now."),
                CopyPair(headline: "Trades tagged \(worst.emotion) have won more often than trades tagged \(best.emotion) in this sample.", suggestion: "The tag alone is not pointing to a weakness right now.")
            )
        )
    }

    private static func resolve(_ draft: Draft) -> Resolved? {
        let count = min(draft.left.metrics.tradeCount, draft.right.metrics.tradeCount)
        guard count >= advancedMinimumTrades else { return nil }
        let gap = performanceGap(draft.left.metrics, draft.right.metrics)
        guard gap.material, let leader = leaderOf(draft.left.metrics, draft.right.metrics, gap: gap) else { return nil }
        let pack = leader.side == "left" ? draft.whenLeftLeads : draft.whenRightLeads
        let copy = leader.byWinRateOnly ? pack.winRate : pack.pnl
        let early = count <= earlyMaximumTrades
        return Resolved(
            id: draft.id,
            category: draft.category,
            title: draft.title,
            left: draft.left,
            right: draft.right,
            favorable: "left",
            rank: draft.rank,
            leader: leader.side,
            byWinRateOnly: leader.byWinRateOnly,
            winRateGap: gap.winRateGap,
            averagePnLGap: gap.averagePnLGap,
            headline: copy.headline,
            suggestion: copy.suggestion,
            sampleLine: sampleLine(draft.left, draft.right, early: early),
            early: early
        )
    }

    private static func guardrails(
        from comparisons: [Resolved],
        preferences: PreferenceRuleContext?,
        enriched: [PsychologyEnrichedTrade]
    ) -> PsychologyCoachGuardrailFacts {
        func find(_ id: String) -> Resolved? {
            comparisons.first { $0.id == id && minCount($0) >= insightMinimumTrades }
        }
        let sleep = find("sleep")
        let stress = find("stress")
        let focus = find("focus")
        let losses = find("afterLosses")
        let frequency = find("tradeFrequency")
        let current = PreferenceComplianceEngine.currentPsychologyRules(in: preferences)
        let personalPause = enriched.contains {
            PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).consecutiveLossPause != nil
        }
        let personalCap = enriched.contains {
            PreferenceComplianceEngine.psychologyRules(in: preferences, at: $0.trade.entryAt).maxTradesPerDay != nil
        }
        let shortSleepWeaker = sleep?.leader == "left"
        return PsychologyCoachGuardrailFacts(
            consecutiveLossCheckpoint: losses?.leader == "left"
                ? (current.consecutiveLossPause ?? (personalPause ? nil : 2))
                : nil,
            consecutiveLossWinRateAfter: doubleValue(losses?.right.metrics.winRate),
            consecutiveLossBaselineWinRate: doubleValue(losses?.left.metrics.winRate),
            lowSleepHoursThreshold: shortSleepWeaker ? 6 : nil,
            lowSleepExpectancy: shortSleepWeaker ? doubleValue(sleep?.right.metrics.averagePnL) : nil,
            maxTradesDaySoftLimit: frequency?.leader == "left"
                ? (current.maxTradesPerDay ?? (personalCap ? nil : 4))
                : nil,
            lateTradeAveragePnL: doubleValue(frequency?.right.metrics.averagePnL),
            earlyTradeAveragePnL: doubleValue(frequency?.left.metrics.averagePnL),
            highStressWeaker: stress?.leader == "left",
            lowFocusWeaker: focus?.leader == "left",
            personalLossPause: current.consecutiveLossPause != nil,
            personalTradeCap: current.maxTradesPerDay != nil
        )
    }

    private static func card(for comparison: Resolved) -> PsychologyInsightCard {
        let count = minCount(comparison)
        return PsychologyInsightCard(
            id: comparison.id,
            category: comparison.category,
            sectionTitle: comparison.title,
            headline: comparison.headline,
            detail: "\(comparison.suggestion) \(comparison.sampleLine)",
            sampleSize: comparison.left.metrics.tradeCount + comparison.right.metrics.tradeCount,
            reliability: count <= earlyMaximumTrades ? .earlySignal : .strong,
            rankingScore: comparison.winRateGap * 100
                + (comparison.averagePnLGap ?? 0) / 50
                + Double(100 - comparison.rank) / 1000
        )
    }

    private static func section(for comparison: Resolved) -> PsychologyAnalyticsSection {
        let leader = comparison.leader == "left" ? comparison.left : comparison.right
        return PsychologyAnalyticsSection(
            id: comparison.id,
            title: comparison.title,
            subtitle: nil,
            groups: [
                PsychologyAnalyticsGroupRow(
                    id: "\(comparison.id).left",
                    label: comparison.left.label,
                    metrics: comparison.left.metrics,
                    highlight: leader.label == comparison.left.label && leader.sampleLabel == comparison.left.sampleLabel
                ),
                PsychologyAnalyticsGroupRow(
                    id: "\(comparison.id).right",
                    label: comparison.right.label,
                    metrics: comparison.right.metrics,
                    highlight: leader.label == comparison.right.label && leader.sampleLabel == comparison.right.sampleLabel
                ),
            ],
            footnote: comparison.sampleLine
        )
    }

    // MARK: - Math

    private struct Gap {
        var winRateGap: Double
        var averagePnLGap: Double?
        var pnlMaterial: Bool
        var material: Bool
    }

    private static func averagePnLGapIsMaterial(_ a: Double, _ b: Double) -> Bool {
        let gap = abs(a - b)
        let scale = max(abs(a), abs(b))
        return gap >= max(minimumAveragePnLGap, scale * pnlGapRatio)
    }

    private static func performanceGap(_ a: PsychologyGroupMetrics, _ b: PsychologyGroupMetrics) -> Gap {
        let leftRate = doubleValue(a.winRate)
        let rightRate = doubleValue(b.winRate)
        let winRateGap = leftRate == nil || rightRate == nil ? 0 : abs(leftRate! - rightRate!)
        let leftPnL = doubleValue(a.averagePnL)
        let rightPnL = doubleValue(b.averagePnL)
        let averagePnLGap = leftPnL == nil || rightPnL == nil ? nil : abs(leftPnL! - rightPnL!)
        let pnlMaterial = leftPnL != nil && rightPnL != nil && averagePnLGapIsMaterial(leftPnL!, rightPnL!)
        return Gap(
            winRateGap: winRateGap,
            averagePnLGap: averagePnLGap,
            pnlMaterial: pnlMaterial,
            material: pnlMaterial || winRateGap >= minimumWinRateGap
        )
    }

    private static func leaderOf(
        _ left: PsychologyGroupMetrics,
        _ right: PsychologyGroupMetrics,
        gap: Gap
    ) -> (side: String, byWinRateOnly: Bool)? {
        guard gap.material else { return nil }
        if gap.pnlMaterial, let leftPnL = doubleValue(left.averagePnL), let rightPnL = doubleValue(right.averagePnL), leftPnL != rightPnL {
            return (leftPnL > rightPnL ? "left" : "right", false)
        }
        if let leftRate = doubleValue(left.winRate), let rightRate = doubleValue(right.winRate), abs(leftRate - rightRate) >= minimumWinRateGap {
            return (leftRate > rightRate ? "left" : "right", true)
        }
        return nil
    }

    private static func sampleLine(_ left: Side, _ right: Side, early: Bool) -> String {
        let body = "Based on \(left.metrics.tradeCount) \(left.sampleLabel) \(tradeWord(left.metrics.tradeCount)) and \(right.metrics.tradeCount) \(right.sampleLabel) \(tradeWord(right.metrics.tradeCount))."
        guard early, let first = body.first else { return body }
        return "Early read, \(String(first).lowercased())\(body.dropFirst())"
    }

    private static func tradeWord(_ count: Int) -> String {
        count == 1 ? "trade" : "trades"
    }

    private static func side(_ label: String, _ sampleLabel: String, _ rows: [PsychologyEnrichedTrade]) -> Side {
        Side(
            label: label,
            sampleLabel: sampleLabel,
            metrics: TraderPsychologyAnalyticsEngine.metrics(for: rows.map(\.trade))
        )
    }

    private static func ratingCopy(
        favorable: String,
        weaker: String
    ) -> (left: (pnl: CopyPair, winRate: CopyPair), right: (pnl: CopyPair, winRate: CopyPair)) {
        let weakerTitle = capitalizedFirst(weaker)
        let favorableTitle = capitalizedFirst(favorable)
        return (
            (
                CopyPair(headline: "You've performed better on \(favorable) days.", suggestion: "Treating \(weaker) days as higher risk may help."),
                CopyPair(headline: "You've won more often on \(favorable) days.", suggestion: "Treating \(weaker) days as higher risk may help.")
            ),
            (
                CopyPair(headline: "\(weakerTitle) days have performed better in this sample.", suggestion: "\(favorableTitle) has not lined up with better results here."),
                CopyPair(headline: "\(weakerTitle) days have won more often in this sample.", suggestion: "\(favorableTitle) has not lined up with more wins here.")
            )
        )
    }

    private static func bandRows(
        _ enriched: [PsychologyEnrichedTrade],
        read: (PsychologyEnrichedTrade) -> Int?,
        high: (Int) -> Bool,
        low: (Int) -> Bool
    ) -> (high: [PsychologyEnrichedTrade], low: [PsychologyEnrichedTrade]) {
        var highRows: [PsychologyEnrichedTrade] = []
        var lowRows: [PsychologyEnrichedTrade] = []
        for row in enriched {
            guard let value = read(row) else { continue }
            if high(value) { highRows.append(row) }
            else if low(value) { lowRows.append(row) }
        }
        return (highRows, lowRows)
    }

    private static func hours(_ row: PsychologyEnrichedTrade) -> Double? {
        guard let hours = row.dailyCheckIn?.sleepHours else { return nil }
        return NSDecimalNumber(decimal: hours).doubleValue
    }

    private static func normalizedEmotion(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return TradeReviewCatalog.emotions.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
    }

    private static func doubleValue(_ value: Decimal?) -> Double? {
        guard let value else { return nil }
        return NSDecimalNumber(decimal: value).doubleValue
    }

    private static func minCount(_ comparison: Resolved) -> Int {
        min(comparison.left.metrics.tradeCount, comparison.right.metrics.tradeCount)
    }

    private static func capitalizedFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}
