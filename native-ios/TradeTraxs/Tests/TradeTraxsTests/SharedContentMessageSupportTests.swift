import XCTest
@testable import TradeTraxs

final class SharedContentMessageSupportTests: XCTestCase {
    private let conversationID = ConversationID("conv-share-caption")
    private let senderID = ProfileID("profile-sender")
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testBundleShareCaptionsPairsTextAfterShare() {
        let share = makeShare(id: "share-1", at: baseDate)
        let note = makeText(id: "text-1", body: "Check this out", at: baseDate.addingTimeInterval(1))
        let bundling = SharedContentMessageSupport.bundleShareCaptions(in: [share, note])

        XCTAssertEqual(bundling.captionByShareID[share.id], "Check this out")
        XCTAssertTrue(bundling.hiddenMessageIDs.contains(note.id))
    }

    func testBundleShareCaptionsPairsTextBeforeShareLegacyOrder() {
        let note = makeText(id: "text-1", body: "Legacy note", at: baseDate)
        let share = makeShare(id: "share-1", at: baseDate.addingTimeInterval(1))
        let bundling = SharedContentMessageSupport.bundleShareCaptions(in: [note, share])

        XCTAssertEqual(bundling.captionByShareID[share.id], "Legacy note")
        XCTAssertTrue(bundling.hiddenMessageIDs.contains(note.id))
    }

    func testBundleShareCaptionsSkipsUnrelatedText() {
        let other = makeText(id: "text-other", body: "Unrelated", at: baseDate.addingTimeInterval(-600))
        let share = makeShare(id: "share-1", at: baseDate)
        let bundling = SharedContentMessageSupport.bundleShareCaptions(in: [other, share])

        XCTAssertNil(bundling.captionByShareID[share.id])
        XCTAssertFalse(bundling.hiddenMessageIDs.contains(other.id))
    }

    func testReconciliationRemovesTradeOnlyShare() {
        let tradeID = TradeID("trade-gone")
        let share = Message(
            id: MessageID("share-trade"),
            conversationID: conversationID,
            senderProfileID: senderID,
            kind: .tradeShare,
            body: nil,
            attachments: SharedContentMessageSupport.tradeShareAttachments(for: tradeID),
            replyToMessageID: nil,
            createdAt: baseDate,
            isReadByViewer: true,
            sharedContent: .trade(tradeID)
        )
        let keys = SharedContentMessageReconciliation.stableKeys(forDeletedTradeID: tradeID)
        let applied = SharedContentMessageReconciliation.apply(to: [share], unavailableKeys: keys)
        XCTAssertTrue(applied.removedIDs.contains(share.id))
        XCTAssertTrue(applied.messages.isEmpty)
    }

    func testReconciliationPreservesCaptionWhenStrippingShare() {
        let postID = PostID("post-gone")
        let share = Message(
            id: MessageID("share-post"),
            conversationID: conversationID,
            senderProfileID: senderID,
            kind: .feedPostShare,
            body: "My commentary",
            attachments: [],
            replyToMessageID: nil,
            createdAt: baseDate,
            isReadByViewer: true,
            sharedContent: .feedPost(postID)
        )
        let keys = SharedContentMessageReconciliation.stableKeys(forDeletedPostID: postID)
        let applied = SharedContentMessageReconciliation.apply(to: [share], unavailableKeys: keys)
        XCTAssertEqual(applied.messages.count, 1)
        XCTAssertEqual(applied.messages[0].kind, .text)
        XCTAssertEqual(applied.messages[0].body, "My commentary")
        XCTAssertNil(applied.messages[0].sharedContent)
    }

    func testShareWithoutCaptionDoesNotReserveSpacing() {
        let share = makeShare(id: "share-1", at: baseDate)
        let item = ConversationBubbleItem(
            id: share.id,
            message: share,
            isOutgoing: true,
            showsAvatar: false,
            showsTimestamp: true,
            sendState: .sent
        )
        XCTAssertNil(item.resolvedShareUserCaption)
        XCTAssertNil(item.copyableMessageText)
    }

    private func makeShare(id: String, at createdAt: Date) -> Message {
        Message(
            id: MessageID(id),
            conversationID: conversationID,
            senderProfileID: senderID,
            kind: .feedPostShare,
            body: nil,
            attachments: [],
            replyToMessageID: nil,
            createdAt: createdAt,
            isReadByViewer: true,
            sharedContent: .feedPost(PostID("post-1"))
        )
    }

    private func makeText(id: String, body: String, at createdAt: Date) -> Message {
        Message(
            id: MessageID(id),
            conversationID: conversationID,
            senderProfileID: senderID,
            kind: .text,
            body: body,
            attachments: [],
            replyToMessageID: nil,
            createdAt: createdAt,
            isReadByViewer: true,
            sharedContent: nil
        )
    }
}
