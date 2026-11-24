import Foundation

/// Single canonical demo journal, dashboard, calendar, trades, profile stats derive from here.
nonisolated enum DemoCanonicalDataset {
    static let profileID = DemoExperienceSupport.profileID

    static let evaluationAccountID = TradingAccountID("demo.account.evaluation")
    static let fundedAccountID = TradingAccountID("demo.account.funded")
    static let liveAccountID = TradingAccountID("demo.account.live")

    /// Eastern-anchored history depth for ``DemoRollingJournal`` (TraxsPro preview uses a 1Y scope).
    static let rollingJournalHistoryMonths = 12

    private static let sampleScreenshotURL =
        "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"

    static func profile(now: Date = Date()) -> Profile {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.viewer
        }
        return DemoExploreIdentity.profile(now: now)
    }

    static func accounts(owner: ProfileID = profileID) -> [TradingAccount] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.accounts.map { account in
                var copy = account
                copy.ownerProfileID = owner
                return copy
            }
        }
        return bundledAccounts(owner: owner)
    }

    private static func bundledAccounts(owner: ProfileID) -> [TradingAccount] {
        [
            TradingAccount(
                id: evaluationAccountID,
                ownerProfileID: owner,
                name: "Apex 50K Evaluation",
                category: .propFirm,
                mode: .evaluation,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "APX-8821",
                propFirmRules: PropFirmAccountRules(
                    consistencyPercent: 40,
                    maxDrawdown: 2_500,
                    dailyDrawdown: 1_200,
                    profitTarget: 3_000,
                    winningDaysRequired: 5,
                    winningDayThreshold: 150,
                    payoutDrawdownBehavior: "keep_trailing"
                )
            ),
            TradingAccount(
                id: fundedAccountID,
                ownerProfileID: owner,
                name: "Apex 50K Funded",
                category: .propFirm,
                mode: .funded,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "APX-9014",
                propFirmRules: PropFirmAccountRules(
                    maxDrawdown: 2_500,
                    dailyDrawdown: 1_200,
                    payoutDrawdownBehavior: "keep_trailing"
                )
            ),
            TradingAccount(
                id: liveAccountID,
                ownerProfileID: owner,
                name: "Tradovate Personal",
                category: .personal,
                mode: .live,
                size: Money(amount: 25_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "TV-44102"
            ),
        ]
    }

    static func accountModes() -> [TradingAccountID: TradingAccountMode] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return Dictionary(snapshot.accounts.map { ($0.id, $0.mode) }, uniquingKeysWith: { _, latest in latest })
        }
        return [
            evaluationAccountID: .evaluation,
            fundedAccountID: .funded,
            liveAccountID: .live,
        ]
    }

    static func trades(now: Date = Date()) -> [Trade] {
        if DemoJournalSourcePolicy.usesRollingJournal {
            return DemoRollingJournal.shared.trades(now: now)
        }
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.trades.sorted { $0.entryAt > $1.entryAt }
        }
        return DemoRollingJournal.shared.trades(now: now)
    }

    static func achievements(owner: ProfileID = profileID) -> [Achievement] {
        DemoGraph.achievements(owner: owner)
    }

    static func posts(owner: ProfileID = profileID) -> [Post] {
        DemoGraph.posts(owner: owner)
    }

    static func clips(owner: ProfileID = profileID) -> [Reel] {
        DemoGraph.clips(owner: owner)
    }

    static func profileStats(from trades: [Trade] = trades()) -> ProfileStats {
        let publicInputs = trades
            .filter { $0.visibility == .public }
            .map { trade in
                ProfileOverviewMetrics.TradeInput(
                    pnl: trade.realizedPnL?.amount,
                    rr: trade.riskReward,
                    mode: trade.mode.rawValue,
                    accountType: nil
                )
            }
        let overview = ProfileOverviewMetrics.compute(from: publicInputs)
        let payoutTotal = ProfilePayoutTotals.sum(from: achievements())
        let allCount = trades.count
        let publicCount = trades.filter { $0.visibility == .public }.count

        return ProfileStats(
            profileID: profileID,
            followerCount: 214,
            followingCount: 86,
            postCount: posts().count,
            tradeCount: allCount,
            publicTradeCount: publicCount,
            winRate: overview.winRate,
            profitFactor: overview.profitFactor,
            netPnL: overview.netPnL,
            averageRR: overview.averageRR,
            payoutTotal: payoutTotal,
            expectancy: nil
        )
    }

    /// Check-ins aligned to the same trade dates as ``trades()``.
    static func checkIns(now: Date = Date()) -> [TraderDailyCheckIn] {
        if DemoJournalSourcePolicy.usesRollingJournal {
            return DemoRollingJournal.shared.checkIns(now: now)
        }
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.checkIns.sorted { $0.checkInDate > $1.checkInDate }
        }
        return DemoRollingJournal.shared.checkIns(now: now)
    }

    static func payoutEntries(for accountID: TradingAccountID, now: Date = Date()) -> [AccountPayoutEntry] {
        if DemoJournalSourcePolicy.usesRollingJournal {
            return DemoRollingJournal.shared.payouts(now: now).filter { $0.accountID == accountID }
        }
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.payouts.filter { $0.accountID == accountID }
        }
        guard accountID == fundedAccountID else { return [] }
        return DemoRollingJournal.shared.payouts(now: now).filter { $0.accountID == accountID }
    }

    /// Trading-rule preferences for interactive TraxsPro Preview (not persisted).
    static func previewPreferenceContext(for userID: ProfileID) -> PreferenceRuleContext {
        var global = TradingRuleTemplates.suggestedGlobal(for: .propFirm) ?? .empty(userID: userID)
        if let dayTrader = TradingRuleTemplates.suggestedGlobal(for: .dayTrader) {
            global.preferredSessions = dayTrader.preferredSessions
            global.plannedStartMinute = dayTrader.plannedStartMinute
            global.plannedEndMinute = dayTrader.plannedEndMinute
            global.minAcceptableRr = dayTrader.minAcceptableRr
            global.targetRr = dayTrader.targetRr
            global.tradingStyle = dayTrader.tradingStyle
        }
        global.userID = userID
        global.consecutiveLossPause = 3
        global.waitAfterLossMinutes = 15
        global.applyRulesToPastTrades = true
        global.personalComplianceTargetPercent = 82
        global.primaryInstruments = ["MES", "MNQ"]
        global.updatedAt = Date()
        return PreferenceRuleContext(revisions: [], global: global, overrides: [])
    }

}

extension DemoCanonicalDataset {
    @MainActor
    static func seedDetailCache(_ cache: DetailPresentationCache, viewer: ProfileID = profileID) {
        cache.seed(profile())
        cache.seed(stats: profileStats())
        cache.seed(accounts: accounts(), for: viewer)
        cache.seed(trades: trades())
        cache.seed(achievements: achievements())
        DemoGraph.seedFeedCache(cache, viewerID: viewer)
    }
}
