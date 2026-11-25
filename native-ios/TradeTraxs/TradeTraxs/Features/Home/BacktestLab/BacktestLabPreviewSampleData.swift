import Foundation

/// In-memory backtest-only sample journal for TraxsPro interactive preview (never persisted).
nonisolated enum BacktestLabPreviewSampleData {
    static let primaryAccountID = TradingAccountID("preview.backtest.account.sessions")
    static let secondaryAccountID = TradingAccountID("preview.backtest.account.swing")

    private static let previewTradeIDPrefix = "preview.backtest.trade."

    static var previewTradeIDs: Set<TradeID> {
        Set(tradeSeeds.map(\.id))
    }

    static func isPreviewTrade(id: TradeID) -> Bool {
        previewTradeIDs.contains(id)
    }

    static func accounts(owner: ProfileID) -> [TradingAccount] {
        [
            TradingAccount(
                id: primaryAccountID,
                ownerProfileID: owner,
                name: "MNQ Session Backtest",
                category: .backtest,
                mode: .backtest,
                size: Money(amount: 25_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "BT-SESSION"
            ),
            TradingAccount(
                id: secondaryAccountID,
                ownerProfileID: owner,
                name: "ES Swing Backtest",
                category: .backtest,
                mode: .backtest,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "BT-SWING"
            ),
        ]
    }

    static func trades(owner: ProfileID, now: Date = Date()) -> [Trade] {
        let calendar = Calendar.current
        return tradeSeeds.map { seed in
            let entryAt = calendar.date(byAdding: .day, value: seed.dayOffset, to: now) ?? now
            let exitAt = calendar.date(byAdding: .minute, value: seed.holdMinutes, to: entryAt) ?? entryAt
            return Trade(
                id: seed.id,
                ownerProfileID: owner,
                accountID: seed.accountID,
                symbol: Symbol(ticker: seed.ticker),
                side: seed.side,
                mode: .backtest,
                quantity: seed.quantity,
                entryPrice: seed.entryPrice,
                exitPrice: seed.exitPrice,
                entryAt: entryAt,
                exitAt: exitAt,
                realizedPnL: Money(amount: seed.pnl),
                riskReward: seed.rr.map { Decimal($0) },
                points: nil,
                sessionLabel: seed.sessionLabel,
                visibility: .private,
                publicCaption: nil,
                thumbnail: nil,
                notePreview: seed.notePreview,
                strategy: seed.strategy,
                createdAt: exitAt,
                updatedAt: exitAt
            )
        }
        .sorted { $0.entryAt > $1.entryAt }
    }

    @MainActor
    static func seedDetailCache(_ cache: DetailPresentationCache, owner: ProfileID) {
        cache.seed(accounts: accounts(owner: owner), for: owner)
        cache.seed(trades: trades(owner: owner))
    }

    private struct TradeSeed {
        let id: TradeID
        let accountID: TradingAccountID
        let ticker: String
        let side: TradeSide
        let quantity: Decimal
        let entryPrice: Decimal
        let exitPrice: Decimal
        let pnl: Decimal
        let rr: Double?
        let strategy: String
        let sessionLabel: String?
        let notePreview: String?
        let dayOffset: Int
        let holdMinutes: Int
    }

    private static let tradeSeeds: [TradeSeed] = [
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)001"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .long,
            quantity: 2,
            entryPrice: 18_420,
            exitPrice: 18_465,
            pnl: 180,
            rr: 2.4,
            strategy: "Fair Value Gap",
            sessionLabel: "NY AM",
            notePreview: "Filled imbalance after 9:45 sweep.",
            dayOffset: -2,
            holdMinutes: 18
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)002"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .short,
            quantity: 1,
            entryPrice: 18_510,
            exitPrice: 18_538,
            pnl: -140,
            rr: 1.0,
            strategy: "Liquidity Sweep",
            sessionLabel: "NY AM",
            notePreview: "Stopped on failed London high sweep.",
            dayOffset: -2,
            holdMinutes: 11
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)003"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .long,
            quantity: 3,
            entryPrice: 18_380,
            exitPrice: 18_428,
            pnl: 288,
            rr: 3.1,
            strategy: "Opening Range Breakout",
            sessionLabel: "NY Open",
            notePreview: "ORB retest held; target prior day high.",
            dayOffset: -5,
            holdMinutes: 34
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)004"),
            accountID: secondaryAccountID,
            ticker: "ES",
            side: .short,
            quantity: 2,
            entryPrice: 5_285,
            exitPrice: 5_292,
            pnl: -175,
            rr: 0.8,
            strategy: "Fair Value Gap",
            sessionLabel: "NY PM",
            notePreview: nil,
            dayOffset: -5,
            holdMinutes: 22
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)005"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .long,
            quantity: 1,
            entryPrice: 18_260,
            exitPrice: 18_302,
            pnl: 84,
            rr: 1.8,
            strategy: "Liquidity Sweep",
            sessionLabel: "London",
            notePreview: "Asia low run + displacement.",
            dayOffset: -8,
            holdMinutes: 27
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)006"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .short,
            quantity: 2,
            entryPrice: 18_330,
            exitPrice: 18_288,
            pnl: 168,
            rr: 2.2,
            strategy: "Opening Range Breakout",
            sessionLabel: "NY Open",
            notePreview: nil,
            dayOffset: -11,
            holdMinutes: 41
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)007"),
            accountID: secondaryAccountID,
            ticker: "ES",
            side: .long,
            quantity: 1,
            entryPrice: 5_240,
            exitPrice: 5_228,
            pnl: -60,
            rr: 1.0,
            strategy: "Fair Value Gap",
            sessionLabel: "NY AM",
            notePreview: "Reversal during CPI volatility.",
            dayOffset: -11,
            holdMinutes: 9
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)008"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .long,
            quantity: 2,
            entryPrice: 18_150,
            exitPrice: 18_198,
            pnl: 192,
            rr: 2.6,
            strategy: "Liquidity Sweep",
            sessionLabel: "NY AM",
            notePreview: nil,
            dayOffset: -14,
            holdMinutes: 16
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)009"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .short,
            quantity: 1,
            entryPrice: 18_220,
            exitPrice: 18_248,
            pnl: -56,
            rr: 0.9,
            strategy: "Opening Range Breakout",
            sessionLabel: "NY Open",
            notePreview: "False break; cut early.",
            dayOffset: -18,
            holdMinutes: 8
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)010"),
            accountID: secondaryAccountID,
            ticker: "ES",
            side: .long,
            quantity: 2,
            entryPrice: 5_198,
            exitPrice: 5_212,
            pnl: 140,
            rr: 1.6,
            strategy: "Opening Range Breakout",
            sessionLabel: "NY PM",
            notePreview: nil,
            dayOffset: -18,
            holdMinutes: 52
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)011"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .long,
            quantity: 3,
            entryPrice: 18_050,
            exitPrice: 18_020,
            pnl: -180,
            rr: 1.0,
            strategy: "Fair Value Gap",
            sessionLabel: "NY AM",
            notePreview: nil,
            dayOffset: -21,
            holdMinutes: 14
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)012"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .short,
            quantity: 2,
            entryPrice: 17_980,
            exitPrice: 17_938,
            pnl: 168,
            rr: 2.0,
            strategy: "Liquidity Sweep",
            sessionLabel: "London",
            notePreview: "PDH sweep into premium array.",
            dayOffset: -24,
            holdMinutes: 31
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)013"),
            accountID: secondaryAccountID,
            ticker: "ES",
            side: .short,
            quantity: 1,
            entryPrice: 5_160,
            exitPrice: 5_148,
            pnl: 60,
            rr: 1.4,
            strategy: "Liquidity Sweep",
            sessionLabel: "NY AM",
            notePreview: nil,
            dayOffset: -27,
            holdMinutes: 25
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)014"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .long,
            quantity: 1,
            entryPrice: 17_880,
            exitPrice: 17_928,
            pnl: 96,
            rr: 2.3,
            strategy: "Opening Range Breakout",
            sessionLabel: "NY Open",
            notePreview: nil,
            dayOffset: -30,
            holdMinutes: 38
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)015"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .short,
            quantity: 2,
            entryPrice: 17_950,
            exitPrice: 17_972,
            pnl: -88,
            rr: 1.0,
            strategy: "Fair Value Gap",
            sessionLabel: "NY PM",
            notePreview: nil,
            dayOffset: -33,
            holdMinutes: 12
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)016"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .long,
            quantity: 2,
            entryPrice: 17_820,
            exitPrice: 17_868,
            pnl: 192,
            rr: 2.8,
            strategy: "Fair Value Gap",
            sessionLabel: "NY AM",
            notePreview: "HTF discount + lower-TF FVG.",
            dayOffset: -36,
            holdMinutes: 21
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)017"),
            accountID: secondaryAccountID,
            ticker: "ES",
            side: .long,
            quantity: 2,
            entryPrice: 5_120,
            exitPrice: 5_106,
            pnl: -70,
            rr: 0.7,
            strategy: "Opening Range Breakout",
            sessionLabel: "NY Open",
            notePreview: nil,
            dayOffset: -40,
            holdMinutes: 15
        ),
        TradeSeed(
            id: TradeID("\(previewTradeIDPrefix)018"),
            accountID: primaryAccountID,
            ticker: "MNQ",
            side: .short,
            quantity: 1,
            entryPrice: 17_760,
            exitPrice: 17_718,
            pnl: 84,
            rr: 1.9,
            strategy: "Liquidity Sweep",
            sessionLabel: "London",
            notePreview: nil,
            dayOffset: -40,
            holdMinutes: 44
        ),
    ]
}