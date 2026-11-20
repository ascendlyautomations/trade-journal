import XCTest
@testable import TradeTraxs

final class BroadcastChatSignalingTests: XCTestCase {
    func testRoundTripReplyPayload() throws {
        let reply = BroadcastChatReplyReference(
            messageId: "host-100",
            userId: "host",
            displayName: "Host",
            textPreview: "Welcome in"
        )
        let data = try BroadcastChatPayload.encodeOutgoing(
            userId: "viewer",
            displayName: "Viewer",
            avatarUrl: nil,
            text: "Thanks!",
            replyTo: reply
        )
        let parsed = BroadcastChatPayload.parseIncoming(data: data, senderIdentity: "viewer")
        XCTAssertEqual(parsed?.replyTo?.messageId, "host-100")
        XCTAssertEqual(parsed?.text, "Thanks!")
    }

    func testIgnoresIncompleteReplySnapshot() throws {
        let json = """
        {"type":"chat","userId":"u1","displayName":"U","text":"hi","sentAt":1,"replyToMessageId":"x-1"}
        """.data(using: .utf8)!
        let parsed = BroadcastChatPayload.parseIncoming(data: json, senderIdentity: "u1")
        XCTAssertEqual(parsed?.text, "hi")
        XCTAssertNil(parsed?.replyTo)
    }

    func testPreviewTruncatesLongText() {
        let long = String(repeating: "a", count: 120)
        let preview = BroadcastChatReplyFormatting.previewText(long)
        XCTAssertEqual(preview.count, TradeRoomBroadcastChatConstants.replyPreviewMaxLength + 1)
        XCTAssertTrue(preview.hasSuffix("…"))
    }
}