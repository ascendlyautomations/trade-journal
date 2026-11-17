import XCTest
@testable import TradeTraxs

final class LinkedContentCaptionDedupTests: XCTestCase {
    func testWhitespaceNormalizedEquivalence() {
        XCTAssertTrue(
            LinkedContentCaptionDedup.areEquivalent(
                "Line one\n\nLine two",
                "  Line one   Line two  "
            )
        )
    }

    func testClipLinkedTradeSectionHidesDuplicateDescription() {
        var trade = ProfileTradeFixtures.samples(owner: ProfileID("dedup.test"))[0]
        trade.publicCaption = "Same journal note"
        let text = ClipLinkedTradeSection.descriptionText(
            for: trade,
            clipCaption: "Same journal note"
        )
        XCTAssertNil(text)
    }

    func testClipLinkedTradeSectionShowsDistinctDescription() {
        var trade = ProfileTradeFixtures.samples(owner: ProfileID("dedup.test"))[0]
        trade.publicCaption = "Trade thesis"
        let text = ClipLinkedTradeSection.descriptionText(
            for: trade,
            clipCaption: "Clip voiceover"
        )
        XCTAssertEqual(text, "Trade thesis")
    }
}
