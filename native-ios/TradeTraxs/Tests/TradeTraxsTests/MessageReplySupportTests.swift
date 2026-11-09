import XCTest
@testable import TradeTraxs

final class MessageReplySupportTests: XCTestCase {
    func testPreviewTextForTradeShare() {
        let message = Message(
            id: MessageID("m1"),
            conversationID: ConversationID("c1"),
            senderProfileID: ProfileID("u1"),
            kind: .tradeShare,
            body: nil,
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        let item = ConversationBubbleItem(
            id: message.id,
            message: message,
            isOutgoing: false,
            showsAvatar: true,
            showsTimestamp: true,
            sendState: .sent
        )
        XCTAssertEqual(MessageReplySupport.previewText(from: item), "Shared a trade")
    }

    func testPreviewTruncatesLongText() {
        let long = String(repeating: "a", count: 120)
        let message = Message(
            id: MessageID("m2"),
            conversationID: ConversationID("c1"),
            senderProfileID: ProfileID("u1"),
            kind: .text,
            body: long,
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        let item = ConversationBubbleItem(
            id: message.id,
            message: message,
            isOutgoing: true,
            showsAvatar: false,
            showsTimestamp: true,
            sendState: .sent
        )
        let preview = MessageReplySupport.previewText(from: item)
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertLessThanOrEqual(preview.count, MessageReplySupport.previewMaxLength + 1)
    }

    func testQuotedAuthorNameUsesProfile() {
        let profile = Profile(
            id: ProfileID("peer"),
            userID: UserID("peer"),
            username: "ada",
            displayName: "Ada Lovelace",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
        let name = MessageReplySupport.quotedAuthorName(
            senderProfileID: profile.id,
            profile: profile,
            viewerID: ProfileID("viewer"),
            peerProfileID: profile.id,
            peerUsername: "ada",
            conversationTitle: "Ada Lovelace"
        )
        XCTAssertEqual(name, "Ada Lovelace")
    }

    func testQuotedAuthorNameFallsBackToPeerUsername() {
        let peerID = ProfileID("peer")
        let name = MessageReplySupport.quotedAuthorName(
            senderProfileID: peerID,
            profile: nil,
            viewerID: ProfileID("viewer"),
            peerProfileID: peerID,
            peerUsername: "ada",
            conversationTitle: nil
        )
        XCTAssertEqual(name, "ada")
    }
}
