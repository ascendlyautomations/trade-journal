import Foundation

/// Deterministic sample trades for DEBUG development sessions / screenshots.
enum ProfileTradeFixtures {
    /// HTTPS sample so ImagePipeline exercises the public-URL branch in DEBUG.
    private static let sampleScreenshotURL =
        "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"

    static func samples(owner profileID: ProfileID) -> [Trade] {
        let now = Date()
        let screenshot = MediaReference(id: sampleScreenshotURL, kind: .image, altText: "Trade screenshot")
        return [
            Trade(
                id: TradeID("dev-trade-1"),
                ownerProfileID: profileID,
                accountID: TradingAccountID("dev-account"),
                symbol: Symbol(ticker: "NQ"),
                side: .long,
                mode: .live,
                quantity: 2,
                entryPrice: 18_420,
                exitPrice: 18_510,
                entryAt: now.addingTimeInterval(-86_400),
                exitAt: now.addingTimeInterval(-85_000),
                realizedPnL: Money(amount: 1_250),
                riskReward: Decimal(string: "2.4"),
                points: 90,
                sessionLabel: "NY",
                visibility: .public,
                publicCaption: "Break and retest",
                thumbnail: screenshot,
                notePreview: "Held through the open drive. Clean level respect.",
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-85_000)
            ),
            Trade(
                id: TradeID("dev-trade-2"),
                ownerProfileID: profileID,
                accountID: TradingAccountID("dev-account"),
                symbol: Symbol(ticker: "ES"),
                side: .short,
                mode: .live,
                quantity: 1,
                entryPrice: 5_210,
                exitPrice: 5_235,
                entryAt: now.addingTimeInterval(-172_800),
                exitAt: now.addingTimeInterval(-170_000),
                realizedPnL: Money(amount: -420),
                riskReward: Decimal(string: "1.1"),
                points: nil,
                sessionLabel: "London",
                visibility: .private,
                publicCaption: nil,
                thumbnail: screenshot,
                notePreview: "Stopped out — late entry.",
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-170_000)
            ),
            Trade(
                id: TradeID("dev-trade-3"),
                ownerProfileID: profileID,
                accountID: TradingAccountID("dev-account-2"),
                symbol: Symbol(ticker: "CL"),
                side: .long,
                mode: .sim,
                quantity: 3,
                entryPrice: 78.4,
                exitPrice: 79.1,
                entryAt: now.addingTimeInterval(-260_000),
                exitAt: now.addingTimeInterval(-255_000),
                realizedPnL: Money(amount: 640),
                riskReward: Decimal(string: "3.0"),
                points: nil,
                sessionLabel: "Asia",
                visibility: .public,
                publicCaption: nil,
                thumbnail: nil,
                notePreview: nil,
                createdAt: now.addingTimeInterval(-260_000),
                updatedAt: now.addingTimeInterval(-255_000)
            ),
            Trade(
                id: TradeID("dev-trade-4"),
                ownerProfileID: profileID,
                accountID: TradingAccountID("dev-account"),
                symbol: Symbol(ticker: "ES"),
                side: .short,
                mode: .live,
                quantity: 2,
                entryPrice: 5_280,
                exitPrice: 5_305,
                entryAt: now.addingTimeInterval(-350_000),
                exitAt: now.addingTimeInterval(-348_000),
                realizedPnL: Money(amount: -510),
                riskReward: Decimal(string: "0.8"),
                points: nil,
                sessionLabel: "London",
                visibility: .public,
                publicCaption: nil,
                thumbnail: screenshot,
                notePreview: nil,
                createdAt: now.addingTimeInterval(-350_000),
                updatedAt: now.addingTimeInterval(-348_000)
            ),
            Trade(
                id: TradeID("dev-trade-5"),
                ownerProfileID: profileID,
                accountID: TradingAccountID("dev-account"),
                symbol: Symbol(ticker: "NQ"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryPrice: 18_100,
                exitPrice: 18_220,
                entryAt: now.addingTimeInterval(-430_000),
                exitAt: now.addingTimeInterval(-428_000),
                realizedPnL: Money(amount: 890),
                riskReward: Decimal(string: "2.0"),
                points: 120,
                sessionLabel: "NY",
                visibility: .public,
                publicCaption: nil,
                thumbnail: screenshot,
                notePreview: nil,
                createdAt: now.addingTimeInterval(-430_000),
                updatedAt: now.addingTimeInterval(-428_000)
            ),
        ]
    }

    /// Broker / prop firm display names (web `accounts.name`).
    static func accountNames() -> [TradingAccountID: String] {
        [
            TradingAccountID("dev-account"): "Alpha Futures",
            TradingAccountID("dev-account-2"): "Tradovate Personal",
        ]
    }

    static func accountModes() -> [TradingAccountID: TradingAccountMode] {
        [
            TradingAccountID("dev-account"): .evaluation,
            TradingAccountID("dev-account-2"): .live,
        ]
    }

    /// Web `accounts.account_size`.
    static func accountSizes() -> [TradingAccountID: Decimal] {
        [
            TradingAccountID("dev-account"): 50_000,
        ]
    }
}
