import XCTest
@testable import TradeTraxs

final class StoryShareMessageSupportTests: XCTestCase {
    private func samplePayloadJSON(
        ownerID: String = "owner-1",
        username: String = "alpha_trader"
    ) -> String {
        """
        {"story_id":"story-1","story_image_url":"https://cdn.example/story.jpg","story_owner_id":"\(ownerID)","story_owner_username":"\(username)"}
        """
    }

    func testDecodeStorySharePayload() {
        let json = samplePayloadJSON()
        let payload = StoryShareMessageSupport.decode(from: json)
        XCTAssertEqual(payload?.storyID, "story-1")
        XCTAssertEqual(payload?.storyOwnerUsername, "alpha_trader")
    }

    func testDecodeRejectsStoryReplyPayload() {
        let json = """
        {"text":"nice","story_id":"story-1","story_image_url":"https://cdn.example/story.jpg","story_owner_id":"owner-1"}
        """
        XCTAssertNil(StoryShareMessageSupport.decode(from: json))
    }

    func testIsStoryShareUsesTypeOrLegacyPayload() {
        let json = samplePayloadJSON()
        XCTAssertTrue(StoryShareMessageSupport.isStoryShare(type: "story_share", content: json))
        XCTAssertTrue(StoryShareMessageSupport.isStoryShare(type: "text", content: json))
        XCTAssertFalse(StoryShareMessageSupport.isStoryShare(type: "voice", content: json))
    }

    func testPreviewTextUsesUsername() {
        let json = samplePayloadJSON()
        XCTAssertEqual(StoryShareMessageSupport.previewText(from: json), "@alpha_trader's story")
    }

    func testContentLinkMatchesDeepLinkPath() {
        XCTAssertEqual(
            DetailContentLink.story(StoryID("abc")).absoluteString,
            "https://www.tradetraxs.com/story/abc"
        )
    }

    func testConversationInboxActivityPreviewForStoryShareMessage() {
        let message = Message(
            id: MessageID("m1"),
            conversationID: ConversationID("c1"),
            senderProfileID: ProfileID("viewer"),
            kind: .storyShare,
            body: samplePayloadJSON(),
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        XCTAssertEqual(ConversationInboxActivity.preview(for: message), "@alpha_trader's story")
    }
}
