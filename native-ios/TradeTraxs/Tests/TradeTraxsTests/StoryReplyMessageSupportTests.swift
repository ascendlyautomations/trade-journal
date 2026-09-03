import XCTest
@testable import TradeTraxs

final class StoryReplyMessageSupportTests: XCTestCase {
    private let viewerID = ProfileID("viewer-1111")
    private let ownerID = ProfileID("owner-2222")

    private func samplePayloadJSON(
        text: String = "fuck yeah dude!!",
        storyID: String = "story-abc",
        imageURL: String = "https://cdn.example/story.jpg",
        ownerID: String = "owner-2222",
        username: String? = "trader_a"
    ) -> String {
        var object: [String: Any] = [
            "text": text,
            "story_id": storyID,
            "story_image_url": imageURL,
            "story_owner_id": ownerID,
        ]
        if let username {
            object["story_owner_username"] = username
        }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    func testDecodeStoryReplyPayload() {
        let json = samplePayloadJSON()
        let payload = StoryReplyMessageSupport.decode(from: json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.text, "fuck yeah dude!!")
        XCTAssertEqual(payload?.storyID, "story-abc")
        XCTAssertEqual(payload?.storyOwnerUsername, "trader_a")
    }

    func testDecodeAllowsMissingStoryImageURL() {
        let json = samplePayloadJSON(imageURL: "")
        XCTAssertNotNil(StoryReplyMessageSupport.decode(from: json))
    }

    func testIsStoryReplyUsesTypeOrLegacyTextPayload() {
        let json = samplePayloadJSON()
        XCTAssertTrue(StoryReplyMessageSupport.isStoryReply(type: "story_reply", content: json))
        XCTAssertTrue(StoryReplyMessageSupport.isStoryReply(type: "text", content: json))
        XCTAssertFalse(StoryReplyMessageSupport.isStoryReply(type: "voice", content: json))
    }

    func testPreviewTextPrefersReplyText() {
        let json = samplePayloadJSON(text: "nice setup")
        XCTAssertEqual(StoryReplyMessageSupport.previewText(from: json), "nice setup")
    }

    func testPreviewTextFallsBackWhenReplyEmpty() {
        let json = samplePayloadJSON(text: "   ")
        XCTAssertEqual(StoryReplyMessageSupport.previewText(from: json), "Replied to a story")
    }

    func testInboxPreviewNeverShowsRawJSON() {
        let json = samplePayloadJSON()
        let preview = StoryReplyMessageSupport.sanitizeInboxPreview(type: "story_reply", content: json)
        XCTAssertEqual(preview, "fuck yeah dude!!")
        XCTAssertFalse(preview?.contains("story_id") ?? true)
    }

    func testContextLabelForOwnStory() {
        let payload = StoryReplyMessageSupport.decode(from: samplePayloadJSON(ownerID: viewerID.rawValue))!
        XCTAssertEqual(
            StoryReplyMessageSupport.contextLabel(payload: payload, viewerProfileID: viewerID),
            "Replied to your story"
        )
    }

    func testContextLabelForPeerStory() {
        let payload = StoryReplyMessageSupport.decode(from: samplePayloadJSON())!
        XCTAssertEqual(
            StoryReplyMessageSupport.contextLabel(payload: payload, viewerProfileID: viewerID),
            "Replied to @trader_a's story"
        )
    }

    func testConversationInboxActivityPreviewForStoryReplyMessage() {
        let message = Message(
            id: MessageID("m-story"),
            conversationID: ConversationID("c1"),
            senderProfileID: ownerID,
            kind: .storyReply,
            body: samplePayloadJSON(),
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        XCTAssertEqual(ConversationInboxActivity.preview(for: message), "fuck yeah dude!!")
    }

    func testConversationBubbleItemTextNeverExposesJSON() {
        let message = Message(
            id: MessageID("m-story"),
            conversationID: ConversationID("c1"),
            senderProfileID: ownerID,
            kind: .storyReply,
            body: samplePayloadJSON(),
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
        XCTAssertEqual(item.text, "fuck yeah dude!!")
        XCTAssertNil(item.imageReference)
    }
}
