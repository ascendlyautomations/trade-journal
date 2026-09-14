import XCTest
@testable import TradeTraxs

final class ReelCaptionTradeLinkTests: XCTestCase {
    func testReelTradeLinkPatchBodyOmitsCaptionField() throws {
        let body = ReelTradeLinkPatchBody(tradeID: "trade-uuid", tradeIsPublic: true)
        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["trade_id"] as? String, "trade-uuid")
        XCTAssertEqual(object["visibility"] as? String, "public")
        XCTAssertNil(object["caption"])
    }

    func testReelPublishPipelineNormalizedCaptionIndependentOfTrade() {
        XCTAssertEqual(
            ReelPublishPipeline.normalizedCaption("Caught this breakout perfectly"),
            "Caught this breakout perfectly"
        )
        XCTAssertNil(ReelPublishPipeline.normalizedCaption("   "))
    }
}
