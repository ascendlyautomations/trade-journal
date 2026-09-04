import Foundation

enum TradeShareFixtures {
    static func sampleTrades(ownerID: ProfileID) -> [Trade] {
        [
            Trade(
                id: TradeID("dev-trade-share-1"),
                ownerProfileID: ownerID,
                accountID: nil,
                symbol: Symbol(ticker: "NQ"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryPrice: 18_420,
                exitPrice: 18_455,
                entryAt: .now.addingTimeInterval(-3_600),
                exitAt: .now.addingTimeInterval(-3_000),
                realizedPnL: Money(amount: 350, currencyCode: "USD"),
                riskReward: 2.1,
                points: 35,
                sessionLabel: "NY",
                visibility: .public,
                publicCaption: nil,
                thumbnail: MediaReference(
                    id: "https://example.com/dev-trade-share.jpg",
                    kind: .image,
                    altText: "Trade screenshot"
                ),
                notePreview: nil,
                createdAt: .now.addingTimeInterval(-3_600),
                updatedAt: .now.addingTimeInterval(-3_000)
            ),
        ]
    }
}
