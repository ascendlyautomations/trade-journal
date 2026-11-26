import Foundation

/// Isolated data plane for an interactive TraxsPro preview — never writes into production session stores.
@MainActor
final class TraxsProPreviewDataEnvironment {
    let viewer: ProfileID
    let feature: TraxsProPreviewFeature
  /// Monotonic token; async preview work must match `generation` on completion.
    private(set) var generation: UInt64

    /// Preview-scoped subgraph passed into preview container view models.
    let data: DataEnvironment

    let trades: [Trade]
    let accounts: [TradingAccount]
    let preferenceContext: PreferenceRuleContext
    let payoutEntriesByAccount: [TradingAccountID: [AccountPayoutEntry]]
    let checkIns: [TraderDailyCheckIn]
    let checkInHistorySummaries: [CheckInHistoryDaySummary]
    let psychologySamplePresentation: PsychologyAnalyticsPreviewSupport.SamplePresentation
    let rulesPresentationStore: TradingRulesComplianceSessionStore
    let scorecardPresentationStore: TradingScorecardSessionStore

    private init(
        viewer: ProfileID,
        feature: TraxsProPreviewFeature,
        generation: UInt64,
        data: DataEnvironment,
        trades: [Trade],
        accounts: [TradingAccount],
        preferenceContext: PreferenceRuleContext,
        payoutEntriesByAccount: [TradingAccountID: [AccountPayoutEntry]],
        checkIns: [TraderDailyCheckIn],
        checkInHistorySummaries: [CheckInHistoryDaySummary],
        psychologySamplePresentation: PsychologyAnalyticsPreviewSupport.SamplePresentation,
        rulesPresentationStore: TradingRulesComplianceSessionStore,
        scorecardPresentationStore: TradingScorecardSessionStore
    ) {
        self.viewer = viewer
        self.feature = feature
        self.generation = generation
        self.data = data
        self.trades = trades
        self.accounts = accounts
        self.preferenceContext = preferenceContext
        self.payoutEntriesByAccount = payoutEntriesByAccount
        self.checkIns = checkIns
        self.checkInHistorySummaries = checkInHistorySummaries
        self.psychologySamplePresentation = psychologySamplePresentation
        self.rulesPresentationStore = rulesPresentationStore
        self.scorecardPresentationStore = scorecardPresentationStore
    }

    static func make(
        from production: DataEnvironment,
        viewer: ProfileID,
        feature: TraxsProPreviewFeature
    ) -> TraxsProPreviewDataEnvironment {
        let generation = TraxsProPreviewSession.shared.bumpPreviewGeneration()
        let detailCache = DetailPresentationCache()
        let trades = DemoCanonicalDataset.trades()
        let accounts = DemoCanonicalDataset.accounts(owner: viewer)
        DemoCanonicalDataset.seedDetailCache(detailCache, viewer: viewer)

        let tradeRepository = DemoTradeRepository(
            ownerID: viewer,
            trades: trades,
            accounts: accounts
        )
        let preferences = TraxsProPreviewInMemoryTradingPreferencesRepository(profileID: viewer)
        let dailyCheckIns = TraxsProPreviewCheckInRepository()

        let tradeDetailRepository = DefaultTradeDetailRepository(
            trades: tradeRepository,
            session: production.session,
            detailCache: detailCache
        )
        let tradingReports = DefaultTradingReportRepository(
            trades: tradeRepository,
            session: production.session,
            detailCache: detailCache,
            tradingPreferences: preferences
        )
        let psychologyReports = DefaultPsychologyReportRepository(
            trades: tradeRepository,
            dailyCheckIns: dailyCheckIns,
            session: production.session,
            detailCache: detailCache,
            tradingPreferences: preferences
        )

        let previewData = production.forking(
            detailCache: detailCache,
            trades: tradeRepository,
            tradeDetailRepository: tradeDetailRepository,
            tradingReports: tradingReports,
            psychologyReports: psychologyReports,
            dailyCheckIns: dailyCheckIns,
            tradingPreferences: preferences
        )

        var payoutEntriesByAccount: [TradingAccountID: [AccountPayoutEntry]] = [:]
        for account in accounts {
            let entries = DemoCanonicalDataset.payoutEntries(for: account.id)
            if !entries.isEmpty {
                payoutEntriesByAccount[account.id] = entries
            }
        }

        let checkIns = DemoCanonicalDataset.checkIns()
        let preferenceContext = DemoCanonicalDataset.previewPreferenceContext(for: viewer)
        let eligibleTrades = trades.filter { $0.mode != .backtest }
        let checkInHistorySummaries = CheckInHistoryAggregator.buildSummaries(
            checkIns: checkIns,
            trades: eligibleTrades
        )
        let psychologySamplePresentation = PsychologyAnalyticsPreviewSupport.buildSamplePresentation(
            trades: eligibleTrades,
            checkIns: checkIns,
            historySummaries: checkInHistorySummaries
        )
        let rulesPresentationStore = TradingRulesComplianceSessionStore()
        let scorecardPresentationStore = TradingScorecardSessionStore()

        return TraxsProPreviewDataEnvironment(
            viewer: viewer,
            feature: feature,
            generation: generation,
            data: previewData,
            trades: trades,
            accounts: accounts,
            preferenceContext: preferenceContext,
            payoutEntriesByAccount: payoutEntriesByAccount,
            checkIns: checkIns,
            checkInHistorySummaries: checkInHistorySummaries,
            psychologySamplePresentation: psychologySamplePresentation,
            rulesPresentationStore: rulesPresentationStore,
            scorecardPresentationStore: scorecardPresentationStore
        )
    }

    func seedBacktestDetailCache() {
        BacktestLabPreviewSampleData.seedDetailCache(
            data.detailCache,
            owner: viewer
        )
    }

    func isCurrentGeneration(_ token: UInt64) -> Bool {
        token == generation
    }

    func invalidateGeneration() {
        generation &+= 1
    }
}