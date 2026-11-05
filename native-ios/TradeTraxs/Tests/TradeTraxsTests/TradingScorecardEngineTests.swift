import XCTest
@testable import TradeTraxs

final class TradingScorecardEngineTests: XCTestCase {
    private func makeTrade(
        index: Int,
        overrides: (inout ScorecardTrade) -> Void = { _ in }
    ) -> ScorecardTrade {
        let day = String(format: "2026-09-%02d", 2 + (index % 8))
        var trade = ScorecardTrade(
            id: "t-\(index)",
            pnl: index % 3 == 0 ? -50 : 80,
            rr: index % 2 == 0 ? 1.5 : nil,
            maxRrReached: index % 4 == 0 ? 1.2 : nil,
            realizedRr: nil,
            followedPlan: nil,
            mistakeType: nil,
            confidence: nil,
            executionRating: nil,
            entryTimeMs: Int64((1_234_567_890 + index * 3600) * 1000),
            tradingDayKey: day,
            psychologyDayKey: day
        )
        overrides(&trade)
        return trade
    }

    private func tradesWithPostLossTags(count: Int, followRate: Double = 0.8) -> [ScorecardTrade] {
        var trades: [ScorecardTrade] = []
        var t = Int64(Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSince1970 * 1000)
        let day = "2026-09-02"
        for i in 0..<count {
            t += 3_600_000
            trades.append(
                makeTrade(index: i * 2) { trade in
                    trade.id = "loss-\(i)"
                    trade.pnl = -40
                    trade.followedPlan = nil
                    trade.entryTimeMs = t
                    trade.tradingDayKey = day
                    trade.psychologyDayKey = day
                }
            )
            t += 3_600_000
            let followed: Bool = followRate >= 1 ? true : (followRate <= 0 ? false : i % 2 == 0)
            trades.append(
                makeTrade(index: i * 2 + 1) { trade in
                    trade.id = "after-\(i)"
                    trade.pnl = 30
                    trade.followedPlan = followed
                    trade.entryTimeMs = t
                    trade.tradingDayKey = day
                    trade.psychologyDayKey = day
                }
            )
        }
        return trades
    }

    func testPlanPoolDoesNotAddTripleLossWhenPostLossSuffices() {
        let trades = tradesWithPostLossTags(count: 12, followRate: 1)
        let post = ScorecardPlanAdherence.postLossPlanObservations(trades: trades)
        let pool = ScorecardPlanAdherence.consistencyPlanAdherencePool(trades: trades)
        XCTAssertGreaterThanOrEqual(post.count, ScorecardPlanAdherence.minPostLossPlanTagged)
        XCTAssertEqual(pool.observations.count, post.count)
        XCTAssertEqual(pool.tripleWindowAddedCount, 0)
    }

    func testConsistencyScoresPostLossNotWinRate() {
        let trades = tradesWithPostLossTags(count: 12, followRate: 1)
        let cat = ScorecardConsistency.score(trades: trades, tradingDayCount: 8, postTripleLossWinRate: 0.2)
        XCTAssertNotNil(cat.score)
        XCTAssertEqual(cat.score, 100)
        XCTAssertTrue(cat.subMetrics.contains { $0.id == "streak.after_three_losses_win_rate" })
    }

    func testConsistencyUnscoredBelowTenPostLossTags() {
        let trades = tradesWithPostLossTags(count: 4, followRate: 1)
        let cat = ScorecardConsistency.score(trades: trades, tradingDayCount: 6, postTripleLossWinRate: nil)
        XCTAssertNil(cat.score)
        XCTAssertFalse(cat.eligible)
    }

    func testRiskNeverScoresPhase1() {
        let trades = (0..<20).map { makeTrade(index: $0) { $0.rr = 2; $0.maxRrReached = 1.5; $0.realizedRr = 1.1 } }
        let rr = DashboardRrTargetAnalysis.compute(from: [])
        let cat = ScorecardRisk.score(trades: trades, maxDrawdown: 500, avgWin: 100, avgLoss: -50, rrTarget: rr)
        XCTAssertNil(cat.score)
        XCTAssertFalse(cat.eligible)
    }

    func testPsychologyInsightsOnly() {
        let trades = (0..<10).map { makeTrade(index: $0) { $0.followedPlan = true } }
        let checkIns = (2...6).map { day -> TraderDailyCheckIn in
            TraderDailyCheckIn(
                id: TraderDailyCheckInID("c-\(day)"),
                ownerProfileID: ProfileID("user"),
                checkInDate: String(format: "2026-09-%02d", day),
                sleepHours: 7,
                sleepQuality: 4,
                morningRating: 4,
                stressLevel: 2,
                energyLevel: 4,
                focusLevel: 4,
                notes: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        let domainTrades: [Trade] = []
        let cat = ScorecardPsychology.score(trades: trades, checkIns: checkIns, domainTrades: domainTrades)
        XCTAssertNil(cat.score)
        XCTAssertFalse(cat.eligible)
        XCTAssertTrue(cat.subMetrics.contains { $0.id == "psych.phase1_mode" })
    }

    func testDisciplineRequiresTenTags() {
        let nine = (0..<9).map { makeTrade(index: $0) { $0.followedPlan = true } }
        XCTAssertNil(ScorecardDiscipline.score(trades: nine).score)
        let ten = (0..<10).map { makeTrade(index: $0) { $0.followedPlan = true } }
        XCTAssertEqual(ScorecardDiscipline.score(trades: ten).score, 100)
    }

    func testOverallBuildingBelowTradeMinimum() {
        let trades = (0..<10).map { makeTrade(index: $0) }
        let result = TradingScorecardBuilder.build(
            input: ScorecardBuildInput(
                scopeLabel: "Test",
                trades: trades,
                checkIns: [],
                analytics: ScorecardAnalyticsContext(
                    periodTradingDayCount: 6,
                    maxDrawdown: 200,
                    avgWin: 100,
                    avgLoss: -50,
                    totalTrades: trades.count,
                    postTripleLossWinRate: nil,
                    rrTargetAnalysis: DashboardRrTargetAnalysis(
                        tradeCount: 10,
                        pairedCount: 0,
                        pairedNonPositiveCount: 0,
                        pairedPositiveCount: 0,
                        avgTargetRr: nil,
                        avgMaxRrReached: nil,
                        avgTargetAttainmentRatio: nil,
                        sampleSummary: nil,
                        headline: nil,
                        bullets: []
                    )
                )
            ),
            domainTrades: []
        )
        XCTAssertEqual(result.overall.status, .building)
        XCTAssertNil(result.overall.score)
        XCTAssertTrue(result.overall.statusMessage.contains(String(ScorecardConstants.minTradesOverall)))
    }

    func testOverallBlockedWithSingleScoredCategory() {
        let trades = (0..<10).map { makeTrade(index: $0) { $0.followedPlan = true } }
        let emptyRR = DashboardRrTargetAnalysis(
            tradeCount: 24,
            pairedCount: 0,
            pairedNonPositiveCount: 0,
            pairedPositiveCount: 0,
            avgTargetRr: nil,
            avgMaxRrReached: nil,
            avgTargetAttainmentRatio: nil,
            sampleSummary: nil,
            headline: nil,
            bullets: []
        )
        let result = TradingScorecardBuilder.build(
            input: ScorecardBuildInput(
                scopeLabel: "Test",
                trades: trades,
                checkIns: [],
                analytics: ScorecardAnalyticsContext(
                    periodTradingDayCount: 6,
                    maxDrawdown: 0,
                    avgWin: 80,
                    avgLoss: -40,
                    totalTrades: 24,
                    postTripleLossWinRate: nil,
                    rrTargetAnalysis: emptyRR
                )
            ),
            domainTrades: []
        )
        XCTAssertEqual(result.overall.status, .building)
        XCTAssertTrue(result.overall.statusMessage.contains("nominal weight"))
    }

    func testOverallReadyWithTwoCategories() {
        var postLoss = tradesWithPostLossTags(count: 12, followRate: 0.75)
        var t = postLoss.last!.entryTimeMs + 3_600_000
        for i in 0..<10 {
            t += 3_600_000
            postLoss.append(
                makeTrade(index: 100 + i) { trade in
                    trade.id = "disc-\(i)"
                    trade.followedPlan = i < 8
                    trade.pnl = 50
                    trade.entryTimeMs = t
                }
            )
        }
        let result = TradingScorecardBuilder.build(
            input: ScorecardBuildInput(
                scopeLabel: "Test scope",
                trades: postLoss,
                checkIns: [],
                analytics: ScorecardAnalyticsContext(
                    periodTradingDayCount: 8,
                    maxDrawdown: 150,
                    avgWin: 90,
                    avgLoss: -45,
                    totalTrades: postLoss.count,
                    postTripleLossWinRate: 0.4,
                    rrTargetAnalysis: DashboardRrTargetAnalysis(
                        tradeCount: postLoss.count,
                        pairedCount: 0,
                        pairedNonPositiveCount: 0,
                        pairedPositiveCount: 0,
                        avgTargetRr: nil,
                        avgMaxRrReached: nil,
                        avgTargetAttainmentRatio: nil,
                        sampleSummary: nil,
                        headline: nil,
                        bullets: []
                    )
                )
            ),
            domainTrades: []
        )
        XCTAssertEqual(result.overall.status, .ready)
        XCTAssertNotNil(result.overall.score)
        XCTAssertGreaterThanOrEqual(result.overall.contributions.count, 2)
        XCTAssertGreaterThanOrEqual(result.overall.nominalWeightIncluded, ScorecardConstants.minNominalWeightOverall)
        let effectiveSum = result.overall.contributions.reduce(0.0) { $0 + $1.effectiveWeight }
        XCTAssertLessThan(abs(effectiveSum - 1), 0.01)
        XCTAssertNil(result.categories.first { $0.id == .risk }?.score)
        XCTAssertNil(result.categories.first { $0.id == .psychology }?.score)
    }

    func testCategoryWeightsSumToOne() {
        let sum = ScorecardConstants.categoryWeights.values.reduce(0, +)
        XCTAssertLessThan(abs(sum - 1), 0.001)
    }

    func testDashboardTradingDayKeySixPmRollover() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 9
        components.day = 2
        components.hour = 19
        components.minute = 0
        let evening = calendar.date(from: components)!
        XCTAssertEqual(DashboardTradingDayKey.key(for: evening), "2026-09-03")
        components.hour = 17
        let before = calendar.date(from: components)!
        XCTAssertEqual(DashboardTradingDayKey.key(for: before), "2026-09-02")
    }

    func testNilFollowedPlanExcludedFromDisciplineDenominator() {
        let trades = (0..<10).map { index in
            makeTrade(index: index) { $0.followedPlan = index == 0 ? true : nil }
        }
        XCTAssertNil(ScorecardDiscipline.score(trades: trades).score)
    }

    func testPostTripleLossWinRateFirstTripleLossWindow() {
        let trades = (0..<5).map { index in
            makeTrade(index: index) { trade in
                trade.pnl = index < 3 ? -10 : 50
            }
        }
        // Mirrors web `postTripleLossWinRate`: first 3 losses, then up to 5 follow-ups (here 2 wins).
        XCTAssertEqual(ScorecardTradeMapper.postTripleLossWinRate(trades: trades), 1.0)
    }

    func testConsistencyBarGateUsesPostLossTagsNotDayCoverage() {
        let trades = (0..<12).map { index in
            makeTrade(index: index) { trade in
                trade.followedPlan = index == 1 ? true : nil
                if index == 0 { trade.pnl = -20 }
            }
        }
        let cat = ScorecardConsistency.score(trades: trades, tradingDayCount: 7, postTripleLossWinRate: nil)
        XCTAssertNil(cat.score)
        XCTAssertGreaterThan(cat.coveragePercent, 80)
        XCTAssertLessThan(ScorecardVisualSupport.categoryBarFillFraction(cat), 0.2)
    }

    func testDisciplineMistakeLoggingCoverageUsesMistakeType() {
        let losses = (0..<4).map { index in
            makeTrade(index: index) { trade in
                trade.pnl = -25
                trade.mistakeType = index < 2 ? "Early exit" : nil
            }
        }
        let cat = ScorecardDiscipline.score(trades: losses)
        let metric = cat.subMetrics.first { $0.id == "discipline.mistake_logging_coverage" }
        XCTAssertNotNil(metric)
        XCTAssertEqual(metric?.value, "50%")
    }
}
