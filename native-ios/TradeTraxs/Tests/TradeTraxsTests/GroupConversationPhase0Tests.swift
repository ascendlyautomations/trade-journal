import XCTest
@testable import TradeTraxs

final class GroupConversationPhase0Tests: XCTestCase {
    func testGroupLeaveSystemMessageBodyMatchesWeb() {
        XCTAssertEqual(
            GroupLeaveSystemMessage.body(displayName: "trader_a"),
            "trader_a left the group"
        )
        XCTAssertEqual(
            GroupLeaveSystemMessage.body(displayName: "  "),
            "Someone left the group"
        )
    }

    func testGroupAvatarUploadUsesConversationScopedPath() {
        let conversationID = ConversationID("11111111-1111-1111-1111-111111111111")
        let path = StorageOptimizedMedia.objectPath(
            prefix: conversationID.rawValue,
            fileExtension: "jpg"
        )
        XCTAssertTrue(path.hasPrefix(conversationID.rawValue))
        XCTAssertTrue(path.contains("/opt/"))
        XCTAssertTrue(path.hasSuffix(".jpg"))
    }
}