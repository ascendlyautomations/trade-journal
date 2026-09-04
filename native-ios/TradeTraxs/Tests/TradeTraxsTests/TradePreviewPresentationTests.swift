import XCTest
@testable import TradeTraxs

final class TradePreviewPresentationTests: XCTestCase {
    func testTradeMediaPresenceUsesThumbnailURL() {
        XCTAssertNotNil(ProfileCardMediaPresence.tradeMedia(in: tradeWithImage))
    }

    func testTradeMediaPresenceNilWhenThumbnailMissing() {
        var trade = tradeWithImage
        trade.thumbnail = nil
        XCTAssertNil(ProfileCardMediaPresence.tradeMedia(in: trade))
    }

    func testTradeMediaPresenceNilWhenURLBlank() {
        var trade = tradeWithImage
        trade.thumbnail = MediaReference(id: "   ", kind: .image, altText: nil)
        XCTAssertNil(ProfileCardMediaPresence.tradeMedia(in: trade))
    }

    private var tradeWithImage: Trade {
        Trade(
            id: TradeID("preview-trade"),
            ownerProfileID: ProfileID("dev.viewer"),
            accountID: nil,
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 24_100,
            exitPrice: 24_125,
            entryAt: Date(),
            exitAt: Date(),
            realizedPnL: Money(amount: 425, currencyCode: "USD"),
            riskReward: 2,
            points: 25,
            sessionLabel: "NY",
            visibility: .public,
            publicCaption: nil,
            thumbnail: MediaReference(id: "https://example.com/trade.jpg", kind: .image, altText: nil),
            notePreview: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
