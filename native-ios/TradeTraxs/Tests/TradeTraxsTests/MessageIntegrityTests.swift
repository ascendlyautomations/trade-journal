import XCTest
@testable import TradeTraxs

@MainActor
final class MessageIntegrityTests: XCTestCase {
    private let conversationID = ConversationID("conv-integrity")
    private let viewer = ProfileID("viewer-1")
    private let peer = ProfileID("peer-1")

    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
    }

    override func tearDown() {
        MessagesInboxStore.shared.resetForTesting()
        super.tearDown()
    }

    // MARK: - Timestamp decoding

    func testSupabaseZTimestampDecodes() {
        let date = ISO8601.date(from: "2026-08-26T15:04:05.123Z")
        XCTAssertNotNil(date)
    }

    func testPlusZeroZeroOffsetTimestampDecodes() {
        let date = ISO8601.date(from: "2026-08-26T15:04:05.123+00:00")
        XCTAssertNotNil(date)
    }

    func testVariableFractionalPrecisionDecodes() {
        XCTAssertNotNil(ISO8601.date(from: "2026-08-26T15:04:05.1Z"))
        XCTAssertNotNil(ISO8601.date(from: "2026-08-26T15:04:05.123456Z"))
    }

    func testMicrosecondPrecisionDecodes() {
        let date = ISO8601.date(from: "2026-08-26T15:04:05.123456Z")
        XCTAssertNotNil(date)
    }

    func testNonUTCOffsetDecodesToAbsoluteInstant() {
        let utc = ISO8601.date(from: "2026-08-26T19:04:05.000Z")
        let offset = ISO8601.date(from: "2026-08-26T15:04:05.000-04:00")
        XCTAssertEqual(utc, offset)
    }

    func testMalformedTimestampReturnsNilNotNow() {
        XCTAssertNil(ISO8601.date(from: "not-a-date"))
        XCTAssertNil(ISO8601.date(from: ""))
    }

    func testMissingTimestampReturnsNilNotNow() {
        XCTAssertNil(ISO8601.date(from: nil))
    }

    func testUTCMidnightCrossingLocalDayBoundaryPreservesInstant() {
        let utc = ISO8601.date(from: "2026-08-26T04:59:00.000Z")!
        let est = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = est
        let day = calendar.component(.day, from: utc)
        XCTAssertEqual(day, 26)
    }

    // MARK: - Thread chronology

    func testMessagesSortAscendingByCreatedAtThenID() {
        let older = makeMessage(id: "b", createdAt: 100)
        let newerSameTime = makeMessage(id: "c", createdAt: 200)
        let newerSameTimeLowerID = makeMessage(id: "a", createdAt: 200)
        let sorted = MessageChronology.sortAscending([newerSameTime, older, newerSameTimeLowerID])
        XCTAssertEqual(sorted.map(\.id.rawValue), ["b", "a", "c"])
    }

    func testEqualTimestampsUseIDTieBreakDescendingForNewestQuery() {
        let a = makeMessage(id: "a", createdAt: 100)
        let b = makeMessage(id: "b", createdAt: 100)
        XCTAssertEqual(MessageChronology.newest(in: [a, b])?.id.rawValue, "b")
    }

    func testOptimisticConfirmationAdoptsServerTimestamp() {
        let temp = makeMessage(id: "temp-abc", body: "hello", createdAt: 100)
        let server = makeMessage(id: "server-1", body: "hello", createdAt: 105)
        let merged = ConversationMessageMerge.mergeMessages(
            existing: [temp],
            incoming: [server],
            viewerID: viewer
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id.rawValue, "server-1")
        XCTAssertEqual(merged[0].createdAt.timeIntervalSince1970, 105)
    }

    func testRealtimeOutOfOrderMergeResortsCorrectly() {
        let first = makeMessage(id: "1", createdAt: 100)
        let third = makeMessage(id: "3", createdAt: 300)
        let second = makeMessage(id: "2", createdAt: 200)
        let merged = ConversationMessageMerge.mergeMessages(
            existing: [first, third],
            incoming: [second],
            viewerID: viewer
        )
        XCTAssertEqual(merged.map(\.id.rawValue), ["1", "2", "3"])
    }

    // MARK: - Inbox activity

    func testEmptyConversationNeverUsesNowForRelativeTimestamp() {
        let label = MessagesInboxSupport.relativeTimestamp(nil)
        XCTAssertEqual(label, "")
    }

    @MainActor
    func testEmptyConversationRowHasNilTimestamp() {
        var empty = makeConversation(id: "empty", preview: nil, at: nil, messageID: nil)
        empty.updatedAt = .distantPast
        let timestamp = empty.lastMessageAt
        XCTAssertNil(timestamp)
        XCTAssertEqual(MessagesInboxSupport.relativeTimestamp(timestamp), "")
    }

    func testBootstrapMapsLastMessageIDFromWireRow() {
        let row = MessagingConversationV1(
            id: "conv-1",
            is_group: false,
            is_pinned: false,
            name: "Peer",
            avatar_url: nil,
            last_message_id: "msg-canonical-1",
            last_message_sender_id: "sender-1",
            last_message_type: "text",
            last_message: "hello",
            last_message_at: "2026-08-26T15:04:05.123Z",
            unread_count: 0,
            muted: false,
            participants: []
        )
        let lastMessageAt = row.last_message_at.flatMap { ISO8601.date(from: $0) }
        let lastMessageID = row.last_message_id.flatMap { raw -> MessageID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : MessageID(trimmed)
        }
        XCTAssertEqual(lastMessageID?.rawValue, "msg-canonical-1")
        XCTAssertNotNil(lastMessageAt)
    }

    func testIncomingWithoutMessageIDDoesNotReplaceExistingAtEqualTimestamp() {
        let existing = makeConversation(id: "dm-1", preview: "local", at: 200, messageID: "msg-local")
        var incoming = existing
        incoming.lastMessageID = nil
        incoming.lastMessagePreview = "server"
        XCTAssertFalse(ConversationInboxActivity.isIncomingActivityNewer(incoming, than: existing))
    }

    @MainActor
    func testBootstrapMergePreservesLocalLastMessageIDAtEqualTimestamp() {
        MessagesInboxStore.shared.resetForTesting()
        let local = makeConversation(id: "dm-1", preview: "local", at: 200, messageID: "msg-local")
        MessagesInboxStore.shared.replaceConversations([local])

        var bootstrap = local
        bootstrap.lastMessageID = nil
        bootstrap.lastMessagePreview = "server"
        bootstrap.lastMessageAt = local.lastMessageAt

        MessagesInboxStore.shared.mergeConversationsFromBootstrap([bootstrap])
        let merged = MessagesInboxStore.shared.conversations.first { $0.id == local.id }
        XCTAssertEqual(merged?.lastMessageID?.rawValue, "msg-local")
    }

    @MainActor
    func testConfirmedSendUpdatesPreviewDateAndOrder() {
        MessagesInboxStore.shared.resetForTesting()
        let older = makeConversation(id: "older", preview: "old", at: 100, messageID: "m1")
        let target = makeConversation(id: "target", preview: "mid", at: 150, messageID: "m2")
        MessagesInboxStore.shared.replaceConversations([older, target])

        let message = makeMessage(id: "m3", body: "fresh", createdAt: 400)
        MessagesInboxStore.shared.patchFromMessage(
            message,
            viewerID: viewer,
            conversationOpen: true,
            policy: .confirmedOutgoing,
            fallbackConversation: target,
            source: "test"
        )

        XCTAssertEqual(MessagesInboxStore.shared.conversations.first?.id, target.id)
        XCTAssertEqual(MessagesInboxStore.shared.conversations.first?.lastMessagePreview, "fresh")
        XCTAssertEqual(MessagesInboxStore.shared.conversations.first?.lastMessageID?.rawValue, "m3")
    }

    @MainActor
    func testBootstrapMapsViewerOutgoingSenderAndSurvivesReplace() {
        MessagesInboxStore.shared.resetForTesting()
        let existing = makeConversation(id: "dm-1", preview: "incoming", at: 100, messageID: "m-in")
        MessagesInboxStore.shared.replaceConversations([existing])

        let row = MessagingConversationV1(
            id: "dm-1",
            is_group: false,
            is_pinned: false,
            name: "Peer",
            avatar_url: nil,
            last_message_id: "msg-outgoing-1",
            last_message_sender_id: viewer.rawValue,
            last_message_type: "text",
            last_message: "viewer sent newest",
            last_message_at: "2026-08-26T18:00:00.000Z",
            unread_count: 0,
            muted: false,
            participants: []
        )
        let lastMessageAt = row.last_message_at.flatMap { ISO8601.date(from: $0) }
        let lastMessageID = row.last_message_id.flatMap { MessageID($0) }
        var bootstrap = existing
        bootstrap.lastMessagePreview = row.last_message
        bootstrap.lastMessageAt = lastMessageAt
        bootstrap.lastMessageID = lastMessageID
        MessagesInboxStore.shared.mergeConversationsFromBootstrap([bootstrap])

        let merged = MessagesInboxStore.shared.conversations.first { $0.id == existing.id }
        XCTAssertEqual(merged?.lastMessagePreview, "viewer sent newest")
        XCTAssertEqual(merged?.lastMessageID?.rawValue, "msg-outgoing-1")
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: merged!), 0)
    }

    func testThreadBootstrapApplierSortsBeforeChoosingLatest() throws {
        let messages = [
            makeMessage(id: "later", body: "newest", createdAt: 200),
            makeMessage(id: "earlier", body: "older", createdAt: 100),
        ]
        let sorted = MessageChronology.sortAscending(messages)
        let latest = MessageChronology.newest(in: sorted)
        XCTAssertEqual(sorted.map(\.id.rawValue), ["earlier", "later"])
        XCTAssertEqual(latest?.id.rawValue, "later")
        XCTAssertEqual(ConversationInboxActivity.preview(for: latest!), "newest")
    }

    // MARK: - Helpers

    private func makeMessage(
        id: String,
        body: String = "text",
        createdAt: TimeInterval
    ) -> Message {
        Message(
            id: MessageID(id),
            conversationID: conversationID,
            senderProfileID: viewer,
            kind: .text,
            body: body,
            attachments: [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: createdAt),
            isReadByViewer: true
        )
    }

    private func makeConversation(
        id: String,
        preview: String?,
        at: TimeInterval?,
        messageID: String?
    ) -> Conversation {
        Conversation(
            id: ConversationID(id),
            participantProfileIDs: [viewer, peer],
            title: "Chat",
            peerUsername: "peer",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: preview,
            lastMessageAt: at.map { Date(timeIntervalSince1970: $0) },
            lastMessageID: messageID.map { MessageID($0) },
            unreadCount: 0,
            isMuted: false,
            updatedAt: at.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        )
    }
}
