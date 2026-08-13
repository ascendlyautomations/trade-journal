import Foundation

/// Deterministic prop-firm account + trades for DEBUG / screenshots / tests.
enum PropFirmFixtures {
    static let accountID = TradingAccountID("dev-account")

    static func accounts(owner profileID: ProfileID) -> [TradingAccount] {
        let names = ProfileTradeFixtures.accountNames()
        let numbers = ProfileTradeFixtures.accountNumbers()
        let modes = ProfileTradeFixtures.accountModes()
        let sizes = ProfileTradeFixtures.accountSizes()
        return names.map { id, name in
            let isProp = id == accountID
            return TradingAccount(
                id: id,
                ownerProfileID: profileID,
                name: name,
                category: isProp ? .propFirm : .personal,
                mode: modes[id] ?? .live,
                size: sizes[id].map { Money(amount: $0) } ?? Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: numbers[id],
                propFirmRules: isProp
                    ? PropFirmAccountRules(
                        consistencyPercent: 40,
                        maxDrawdown: 2_000,
                        dailyDrawdown: 1_000,
                        profitTarget: 3_000,
                        winningDaysRequired: 5,
                        winningDayThreshold: nil,
                        payoutDrawdownBehavior: "keep_trailing"
                    )
                    : nil
            )
        }
    }

    static func trades(owner profileID: ProfileID, accountID: TradingAccountID) -> [Trade] {
        ProfileTradeFixtures.samples(owner: profileID)
            .map { trade in
                var copy = trade
                if copy.accountID == nil {
                    copy.accountID = accountID
                }
                return copy
            }
            .filter { $0.accountID == accountID }
    }
}
