import XCTest
@testable import TradeTraxs

final class ConversationMessageMergeTests: XCTestCase {
    private let viewer = ProfileID("viewer-1")
    private let peer = ProfileID("peer-1")
    private let conversation = ConversationID("c1")

    func testMergeMessagesUpsertsByIDWithoutDuplicates() {
        let first = makeMessage(id: "a", body: "hi", sender: peer, at: 100, read: false)
        let updated = makeMessage(id: "a", body: "hi!", sender: peer, at: 100, read: true)
        let second = makeMessage(id: "b", body: "yo", sender: viewer, at: 200, read: true)

        let merged = ConversationMessageMerge.mergeMessages(
            existing: [first, first],
            incoming: [updated, second],
            viewerID: viewer
        )

        XCTAssertEqual(merged.map(\.id.rawValue), ["a", "b"])
        XCTAssertEqual(merged.first?.body, "hi!")
        XCTAssertTrue(merged.first?.isReadByViewer == true)
        XCTAssertEqual(Set(merged.map(\.id)).count, merged.count)
    }

    func testRealtimeReplacesOptimisticTempMessage() {
        let temp = makeMessage(
            id: "temp-abc",
            body: "hello",
            sender: viewer,
            at: 1_000,
            read: true
        )
        let server = makeMessage(
            id: "server-1",
            body: "hello",
            sender: viewer,
            at: 1_005,
            read: true
        )

        let merged = ConversationMessageMerge.mergeMessages(
            existing: [temp],
            incoming: [server],
            viewerID: viewer
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id.rawValue, "server-1")
        XCTAssertFalse(merged.contains { $0.id.rawValue.hasPrefix("temp-") })
    }

    func testRealtimeDoesNotDuplicateWhenServerAlreadyPresent() {
        let server = makeMessage(id: "server-1", body: "hello", sender: viewer, at: 1_000, read: true)
        let temp = makeMessage(id: "temp-abc", body: "hello", sender: viewer, at: 1_001, read: true)

        // Server arrived first via realtime; send confirmation merges again.
        let merged = ConversationMessageMerge.mergeMessages(
            existing: [server, temp],
            incoming: [server],
            viewerID: viewer
        )

        // Temp should be replaced / collapsed — only one bubble for this send.
        let hellos = merged.filter { $0.body == "hello" && $0.senderProfileID == viewer }
        XCTAssertEqual(hellos.count, 1)
        XCTAssertEqual(hellos[0].id.rawValue, "server-1")
    }

    func testPaginationMergePreservesOrderAndUniqueness() {
        let older = makeMessage(id: "old", body: "old", sender: peer, at: 50, read: true)
        let newer = makeMessage(id: "new", body: "new", sender: peer, at: 150, read: true)
        let overlap = makeMessage(id: "new", body: "new-updated", sender: peer, at: 150, read: true)

        let merged = ConversationMessageMerge.mergeMessages(
            existing: [newer],
            incoming: [older, overlap],
            viewerID: viewer
        )

        XCTAssertEqual(merged.map(\.id.rawValue), ["old", "new"])
        XCTAssertEqual(merged.last?.body, "new-updated")
    }

    func testPreservesAttachmentsWhenIncomingIsThin() {
        let rich = Message(
            id: MessageID("m1"),
            conversationID: conversation,
            senderProfileID: peer,
            kind: .media,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: "https://cdn.example/a.jpg",
                    media: MediaReference(id: "https://cdn.example/a.jpg", kind: .image, altText: nil),
                    tradeID: nil
                ),
            ],
            replyToMessageID: MessageID("parent"),
            createdAt: Date(timeIntervalSince1970: 100),
            isReadByViewer: true
        )
        let thin = makeMessage(id: "m1", body: nil, sender: peer, at: 100, read: false)

        let merged = ConversationMessageMerge.mergeMessages(
            existing: [rich],
            incoming: [thin],
            viewerID: viewer
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].attachments.isEmpty)
        XCTAssertEqual(merged[0].replyToMessageID?.rawValue, "parent")
        XCTAssertTrue(merged[0].isReadByViewer)
    }

    // MARK: - Helpers

    private func makeMessage(
        id: String,
        body: String?,
        sender: ProfileID,
        at: TimeInterval,
        read: Bool
    ) -> Message {
        Message(
            id: MessageID(id),
            conversationID: conversation,
            senderProfileID: sender,
            kind: .text,
            body: body,
            attachments: [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: at),
            isReadByViewer: read
        )
    }
}
