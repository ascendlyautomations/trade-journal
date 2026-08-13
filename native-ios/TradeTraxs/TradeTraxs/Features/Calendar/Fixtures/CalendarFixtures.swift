import Foundation

enum CalendarFixtures {
    static let viewerID = ProfileID("dev.calendar.viewer")

    /// Mix of profitable / losing / breakeven days in the current NY trading month.
    nonisolated static func trades(owner profileID: ProfileID, now: Date = Date()) -> [Trade] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TradingCalendarDay.timeZone
        let comps = calendar.dateComponents([.year, .month], from: now)
        let year = comps.year ?? 2026
        let month = comps.month ?? 8

        func day(_ d: Int, hour: Int = 10) -> Date {
            calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: TradingCalendarDay.timeZone,
                year: year,
                month: month,
                day: d,
                hour: hour,
                minute: 30
            )) ?? now
        }

        let personal = TradingAccountID("dev.calendar.personal")
        let prop = TradingAccountID("dev.calendar.prop")

        return [
            make(id: "c-1", owner: profileID, account: personal, symbol: "NQ", entry: day(3), pnl: 420, side: .long),
            make(id: "c-2", owner: profileID, account: personal, symbol: "ES", entry: day(3, hour: 14), pnl: 180, side: .short),
            make(id: "c-3", owner: profileID, account: personal, symbol: "NQ", entry: day(5), pnl: -215, side: .long),
            make(id: "c-4", owner: profileID, account: prop, symbol: "NQ", entry: day(8), pnl: 842, side: .long),
            make(id: "c-5", owner: profileID, account: prop, symbol: "ES", entry: day(8, hour: 13), pnl: -120, side: .short),
            make(id: "c-6", owner: profileID, account: prop, symbol: "NQ", entry: day(8, hour: 15), pnl: 95, side: .long),
            make(id: "c-7", owner: profileID, account: personal, symbol: "YM", entry: day(12), pnl: 0, side: .long),
            make(id: "c-8", owner: profileID, account: personal, symbol: "NQ", entry: day(15), pnl: -55, side: .short),
            make(id: "c-9", owner: profileID, account: personal, symbol: "ES", entry: day(15, hour: 11), pnl: -90, side: .long),
            make(id: "c-10", owner: profileID, account: prop, symbol: "NQ", entry: day(20), pnl: 1_240, side: .long),
            // After 18:00 ET → next trading day
            make(
                id: "c-11",
                owner: profileID,
                account: personal,
                symbol: "NQ",
                entry: day(21, hour: 19),
                pnl: 310,
                side: .long
            ),
        ]
    }

    nonisolated static func accounts(owner profileID: ProfileID) -> [TradingAccount] {
        [
            TradingAccount(
                id: TradingAccountID("dev.calendar.personal"),
                ownerProfileID: profileID,
                name: "Personal Sim",
                category: .personal,
                mode: .sim,
                size: Money(amount: 25_000),
                isActive: true,
                canAddTrades: true
            ),
            TradingAccount(
                id: TradingAccountID("dev.calendar.prop"),
                ownerProfileID: profileID,
                name: "Alpha Futures 50K PROP",
                category: .propFirm,
                mode: .evaluation,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                propFirmRules: PropFirmAccountRules(maxDrawdown: 2_000, profitTarget: 3_000)
            ),
        ]
    }

    nonisolated private static func make(
        id: String,
        owner: ProfileID,
        account: TradingAccountID,
        symbol: String,
        entry: Date,
        pnl: Decimal,
        side: TradeSide
    ) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: owner,
            accountID: account,
            symbol: Symbol(ticker: symbol),
            side: side,
            mode: .live,
            quantity: 1,
            entryPrice: 18_000,
            exitPrice: 18_010,
            entryAt: entry,
            exitAt: entry.addingTimeInterval(3_600),
            realizedPnL: Money(amount: pnl),
            riskReward: 2,
            points: 10,
            sessionLabel: "NY",
            visibility: .public,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: entry,
            updatedAt: entry
        )
    }
}
