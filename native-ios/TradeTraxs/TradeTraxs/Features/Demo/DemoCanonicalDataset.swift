import Foundation

/// Single canonical demo journal — dashboard, calendar, trades, profile stats derive from here.
nonisolated enum DemoCanonicalDataset {
    static let profileID = DemoExperienceSupport.profileID

    static let evaluationAccountID = TradingAccountID("demo.account.evaluation")
    static let fundedAccountID = TradingAccountID("demo.account.funded")
    static let liveAccountID = TradingAccountID("demo.account.live")

    private static let sampleScreenshotURL =
        "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"

    static func profile(now: Date = Date()) -> Profile {
        DemoExploreIdentity.profile(now: now)
    }

    static func accounts(owner: ProfileID = profileID) -> [TradingAccount] {
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
        [
            evaluationAccountID: .evaluation,
            fundedAccountID: .funded,
            liveAccountID: .live,
        ]
    }

    static func trades(now: Date = Date()) -> [Trade] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone

        let symbols = ["NQ", "MNQ", "ES"]
        let sides: [TradeSide] = [.long, .short]
        let accounts = [evaluationAccountID, fundedAccountID, liveAccountID]
        let strategies = [
            "Opening drive",
            "Liquidity sweep",
            "VWAP rejection",
            "Failed breakdown",
            "NY lunch fade",
        ]

        var result: [Trade] = []
        result.reserveCapacity(48)

        // Anchor recent activity in the current month + prior ~90 calendar days.
        for dayOffset in stride(from: -92, through: 0, by: 3) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let tradesThisDay = dayOffset % 9 == 0 ? 2 : 1
            for index in 0..<tradesThisDay {
                let symbol = symbols[(abs(dayOffset) + index) % symbols.count]
                let side = sides[(abs(dayOffset) + index) % sides.count]
                let account = accounts[(abs(dayOffset) + index) % accounts.count]
                let hour = 9 + (index * 2) + (abs(dayOffset) % 4)
                var comps = calendar.dateComponents([.year, .month, .day], from: day)
                comps.hour = min(hour, 15)
                comps.minute = 15 + (index * 20)
                comps.timeZone = TradingCalendarDay.timeZone
                let entry = calendar.date(from: comps) ?? day
                let exit = entry.addingTimeInterval(TimeInterval(1_800 + (index * 600)))

                let seed = abs(dayOffset) * 10 + index
                let pnl: Decimal = {
                    switch seed % 7 {
                    case 0: return -180 - Decimal(seed % 5) * 40
                    case 1: return -95
                    case 2: return 0
                    default: return 120 + Decimal(seed % 6) * 85
                    }
                }()

                let qty: Decimal = symbol == "MNQ" ? 4 : (symbol == "NQ" ? 2 : 1)
                let entryPrice: Decimal = symbol.hasPrefix("ES") ? 5_200 + Decimal(seed % 40) : 18_400 + Decimal(seed % 80)
                let points = pnl == 0 ? Decimal(0) : (pnl > 0 ? Decimal(18 + seed % 12) : Decimal(-8 - seed % 6))
                let exitPrice = entryPrice + (side == .long ? points : -points)
                let rr = Decimal(string: String(format: "%.1f", 0.8 + Double(seed % 5) * 0.35))
                let hasNotes = seed % 4 == 0
                let isPublic = seed % 5 != 1
                let screenshot = seed % 3 == 0
                    ? MediaReference(id: sampleScreenshotURL, kind: .image, altText: "Chart")
                    : nil

                result.append(
                    Trade(
                        id: TradeID("demo-trade-\(abs(dayOffset))-\(index)"),
                        ownerProfileID: profileID,
                        accountID: account,
                        symbol: Symbol(ticker: symbol),
                        side: side,
                        mode: account == liveAccountID ? .live : .sim,
                        quantity: qty,
                        entryPrice: entryPrice,
                        exitPrice: exitPrice,
                        entryAt: entry,
                        exitAt: exit,
                        realizedPnL: Money(amount: pnl),
                        riskReward: rr,
                        points: abs(points),
                        sessionLabel: hour < 12 ? "NY" : "NY PM",
                        visibility: isPublic ? .public : .private,
                        publicCaption: isPublic ? "Session recap" : nil,
                        thumbnail: screenshot,
                        notePreview: hasNotes ? "Waited for confirmation; sized to plan." : nil,
                        strategy: strategies[seed % strategies.count],
                        createdAt: entry,
                        updatedAt: exit
                    )
                )
            }
        }

        return result.sorted { $0.entryAt > $1.entryAt }
    }

    static func achievements(owner: ProfileID = profileID) -> [Achievement] {
        ProfileAchievementFixtures.samples(owner: owner)
    }

    static func posts(owner: ProfileID = profileID) -> [Post] {
        ProfilePostFixtures.samples(owner: owner)
    }

    static func clips(owner: ProfileID = profileID) -> [Reel] {
        ProfileClipFixtures.samples(owner: owner)
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

    static func payoutEntries(for accountID: TradingAccountID) -> [AccountPayoutEntry] {
        guard accountID == fundedAccountID else { return [] }
        let now = Date()
        return [
            AccountPayoutEntry(
                id: AccountPayoutEntryID("demo-payout-1"),
                accountID: accountID,
                amount: Money(amount: 1_850),
                payoutDate: now.addingTimeInterval(-86_400 * 45),
                note: "First funded payout"
            ),
            AccountPayoutEntry(
                id: AccountPayoutEntryID("demo-payout-2"),
                accountID: accountID,
                amount: Money(amount: 2_400),
                payoutDate: now.addingTimeInterval(-86_400 * 18),
                note: "Consistency week"
            ),
        ]
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
        FeedFixtures.seedDetailCache(cache, viewerID: viewer)
    }
}
