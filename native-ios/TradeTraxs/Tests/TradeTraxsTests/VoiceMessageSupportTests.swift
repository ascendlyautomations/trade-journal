import XCTest
@testable import TradeTraxs

final class VoiceMessageSupportTests: XCTestCase {
    func testFormatDuration() {
        XCTAssertEqual(VoiceMessageSupport.formatDuration(14.6), "0:14")
        XCTAssertEqual(VoiceMessageSupport.formatDuration(74), "1:14")
    }

    func testVoicePreviewText() {
        let message = Message(
            id: MessageID("m1"),
            conversationID: ConversationID("c1"),
            senderProfileID: ProfileID("viewer"),
            kind: .voice,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: "https://example.com/voice.m4a",
                    media: MediaReference(id: "https://example.com/voice.m4a", kind: .audio, altText: nil),
                    tradeID: nil,
                    durationSeconds: 12
                ),
            ],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        XCTAssertEqual(ConversationInboxActivity.preview(for: message), "Voice message")
    }

    func testVoiceContentKeyUsesDurationFingerprint() {
        let message = Message(
            id: MessageID("temp-1"),
            conversationID: ConversationID("c1"),
            senderProfileID: ProfileID("viewer"),
            kind: .voice,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: "local",
                    media: MediaReference(id: "local", kind: .audio, altText: nil),
                    tradeID: nil,
                    durationSeconds: 3.2
                ),
            ],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        XCTAssertEqual(ConversationMessageMerge.contentKey(for: message), "voice:3200")
    }
}
