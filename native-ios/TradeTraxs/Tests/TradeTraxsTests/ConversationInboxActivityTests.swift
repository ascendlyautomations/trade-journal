import XCTest
@testable import TradeTraxs

@MainActor
final class ConversationInboxActivityTests: XCTestCase {
    private let viewer = ProfileID("viewer-1")
    private let peer = ProfileID("peer-a")

    override func setUp() async throws {
        MessagesInboxStore.shared.resetForTesting()
        DirectConversationPairIndex.shared.invalidate()
    }

    override func tearDown() {
        MessagesInboxStore.shared.resetForTesting()
        DirectConversationPairIndex.shared.invalidate()
        super.tearDown()
    }

    // MARK: - Pair index

    func testDirectPairKeyIsOrderIndependent() {
        let forward = DirectConversationPairIndex.pairKey(viewer, peer)
        let reversed = DirectConversationPairIndex.pairKey(peer, viewer)
        XCTAssertEqual(forward, reversed)
        XCTAssertTrue(forward.contains("|"))
    }

    func testPairKeyNormalizesUUIDCase() {
        let upper = ProfileID("AAAA-BBBB-CCCC")
        let lower = ProfileID("aaaa-bbbb-cccc")
        XCTAssertEqual(
            DirectConversationPairIndex.pairKey(upper, peer),
            DirectConversationPairIndex.pairKey(lower, peer)
        )
    }

    func testDuplicateDirectDataKeepsLexicographicallySmallestID() {
        let smaller = makeDirectConversation(
            id: ConversationID("aaa-dm"),
            participants: [viewer, peer]
        )
        let larger = makeDirectConversation(
            id: ConversationID("zzz-dm"),
            participants: [viewer, peer]
        )
        DirectConversationPairIndex.shared.register(conversation: larger)
        DirectConversationPairIndex.shared.register(conversation: smaller)
        XCTAssertEqual(
            DirectConversationPairIndex.shared.conversationID(viewerID: viewer, recipientID: peer),
            smaller.id
        )
    }

    func testGroupConversationIsNotRegisteredInPairIndex() {
        var group = makeDirectConversation(id: ConversationID("group-1"), participants: [viewer, peer])
        group.isGroup = true
        DirectConversationPairIndex.shared.register(conversation: group)
        XCTAssertNil(DirectConversationPairIndex.shared.conversationID(viewerID: viewer, recipientID: peer))
    }

    // MARK: - Preview + ordering

    func testSendingMessageMovesConversationToTop() {
        let older = makeConversation(
            id: "older",
            preview: "old",
            at: 100,
            messageID: "m-old"
        )
        let newer = makeConversation(
            id: "newer",
            preview: "mid",
            at: 200,
            messageID: "m-mid"
        )
        MessagesInboxStore.shared.replaceConversations([older, newer])

        let message = makeMessage(
            id: "m-fresh",
            conversationID: older.id,
            body: "fresh",
            at: 300
        )
        MessagesInboxStore.shared.patchFromMessage(message, viewerID: viewer, conversationOpen: true)

        XCTAssertEqual(MessagesInboxStore.shared.visibleConversations.first?.id, older.id)
        XCTAssertEqual(MessagesInboxStore.shared.visibleConversations.first?.lastMessagePreview, "fresh")
    }

    func testIncomingMessageIncrementsUnreadWhenConversationClosed() {
        let conversation = makeConversation(
            id: "inbox-dm",
            preview: "hi",
            at: 100,
            messageID: "m1"
        )
        MessagesInboxStore.shared.replaceConversations([conversation])

        let incoming = makeMessage(
            id: "m2",
            conversationID: conversation.id,
            sender: peer,
            body: "reply",
            at: 200
        )
        MessagesInboxStore.shared.patchFromMessage(incoming, viewerID: viewer, conversationOpen: false)

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: row), 1)
        XCTAssertEqual(row.lastMessagePreview, "reply")
    }

    func testLateOlderRealtimeCannotReplaceNewerPreview() {
        var conversation = makeConversation(
            id: "dm",
            preview: "B",
            at: 200,
            messageID: "m-b"
        )
        conversation.lastMessageID = MessageID("m-b")
        MessagesInboxStore.shared.replaceConversations([conversation])

        let stale = makeMessage(
            id: "m-a",
            conversationID: conversation.id,
            body: "A",
            at: 100
        )
        MessagesInboxStore.shared.patchFromMessage(stale, viewerID: viewer, conversationOpen: true)

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(row.lastMessagePreview, "B")
        XCTAssertEqual(row.lastMessageID, MessageID("m-b"))
    }

    func testBootstrapMergePreservesNewerLocalPreview() {
        let local = makeConversation(
            id: "dm",
            preview: "local-new",
            at: 300,
            messageID: "local-id"
        )
        MessagesInboxStore.shared.replaceConversations([local])

        let bootstrap = makeConversation(
            id: "dm",
            preview: "server-old",
            at: 100,
            messageID: "server-id"
        )
        MessagesInboxStore.shared.mergeConversationsFromBootstrap([bootstrap])

        let row = MessagesInboxStore.shared.conversations.first { $0.id == local.id }!
        XCTAssertEqual(row.lastMessagePreview, "local-new")
        XCTAssertEqual(row.lastMessageAt, Date(timeIntervalSince1970: 300))
    }

    func testEqualTimestampUsesMessageIDTieBreakForSort() {
        let a = makeConversation(id: "a", preview: "a", at: 500, messageID: "m-a")
        let b = makeConversation(id: "b", preview: "b", at: 500, messageID: "m-z")
        MessagesInboxStore.shared.replaceConversations([a, b])
        XCTAssertEqual(MessagesInboxStore.shared.visibleConversations.first?.id, b.id)
    }

    func testAttachmentOnlyPreviewUsesFallbackText() {
        let message = Message(
            id: MessageID("m-photo"),
            conversationID: ConversationID("c1"),
            senderProfileID: viewer,
            kind: .media,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: "img",
                    media: MediaReference(id: "img", kind: .image, altText: nil),
                    tradeID: nil
                ),
            ],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        XCTAssertEqual(ConversationInboxActivity.preview(for: message), "Photo")
    }

    func testConfirmedOutgoingAlwaysUpdatesPreview() {
        let conversationID = ConversationID("dm")
        let existing = makeConversation(
            id: "dm",
            preview: "older",
            at: 200,
            messageID: "m-zzz"
        )
        let saved = makeMessage(
            id: "m-aaa",
            conversationID: conversationID,
            body: "newest",
            at: 200
        )
        let patched = ConversationInboxActivity.applyingConfirmedSendActivity(to: existing, message: saved)
        XCTAssertEqual(patched.lastMessageID, MessageID("m-aaa"))
        XCTAssertEqual(patched.lastMessagePreview, "newest")
    }

    func testTradeSharePreviewUsesFallbackText() {
        let message = Message(
            id: MessageID("m-trade"),
            conversationID: ConversationID("c1"),
            senderProfileID: viewer,
            kind: .tradeShare,
            body: nil,
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        XCTAssertEqual(ConversationInboxActivity.preview(for: message), "Shared a trade")
    }

    func testIsMessageNewerUsesCreatedAtThenID() {
        let older = makeMessage(id: "a", conversationID: ConversationID("c"), body: "a", at: 100)
        let newer = makeMessage(id: "b", conversationID: ConversationID("c"), body: "b", at: 200)
        XCTAssertTrue(ConversationInboxActivity.isMessageNewer(newer, than: older))
        XCTAssertFalse(ConversationInboxActivity.isMessageNewer(older, than: newer))
    }

    func testOutgoingSendDoesNotIncrementUnread() {
        var conversation = makeConversation(
            id: "dm",
            preview: "hi",
            at: 100,
            messageID: "m1"
        )
        conversation.unreadCount = 0
        MessagesInboxStore.shared.replaceConversations([conversation])

        let outgoing = makeMessage(
            id: "m-out",
            conversationID: conversation.id,
            body: "sent by me",
            at: 200
        )
        MessagesInboxStore.shared.patchFromMessage(
            outgoing,
            viewerID: viewer,
            conversationOpen: false,
            policy: .confirmedOutgoing
        )

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: row), 0)
        XCTAssertEqual(row.lastMessagePreview, "sent by me")
    }

    func testOutgoingReplacesIncomingPreviewWhenNewer() {
        let conversation = makeConversation(
            id: "dm",
            preview: "incoming",
            at: 100,
            messageID: "m-in"
        )
        MessagesInboxStore.shared.replaceConversations([conversation])

        let outgoing = makeMessage(
            id: "m-out",
            conversationID: conversation.id,
            body: "my reply",
            at: 200
        )
        MessagesInboxStore.shared.patchFromMessage(
            outgoing,
            viewerID: viewer,
            policy: .confirmedOutgoing,
            fallbackConversation: conversation
        )

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(row.lastMessagePreview, "my reply")
        XCTAssertEqual(row.lastMessageID, MessageID("m-out"))
    }

    func testIncomingReplyReplacesOutgoingPreviewWhenNewer() {
        let conversation = makeConversation(
            id: "dm",
            preview: "mine",
            at: 200,
            messageID: "m-out"
        )
        MessagesInboxStore.shared.replaceConversations([conversation])

        let incoming = makeMessage(
            id: "m-in",
            conversationID: conversation.id,
            sender: peer,
            body: "peer reply",
            at: 300
        )
        MessagesInboxStore.shared.patchFromMessage(
            incoming,
            viewerID: viewer,
            conversationOpen: false
        )

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(row.lastMessagePreview, "peer reply")
        XCTAssertEqual(row.lastMessageID, MessageID("m-in"))
    }

    func testFullyReadConversationKeepsLatestPreview() {
        var conversation = makeConversation(
            id: "dm",
            preview: "old",
            at: 100,
            messageID: "m-old"
        )
        conversation.unreadCount = 0
        MessagesInboxStore.shared.replaceConversations([conversation])

        let bootstrap = makeConversation(
            id: "dm",
            preview: "canonical latest",
            at: 400,
            messageID: "m-latest"
        )
        MessagesInboxStore.shared.mergeConversationsFromBootstrap([bootstrap])

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(row.lastMessagePreview, "canonical latest")
        XCTAssertEqual(MessagesInboxStore.shared.unreadCount(for: row), 0)
    }

    func testGroupOutgoingMessageMovesToTop() {
        var top = makeConversation(id: "top", preview: "top", at: 500, messageID: "m-top")
        top.isGroup = true
        var group = makeConversation(id: "group", preview: "old", at: 100, messageID: "m-old")
        group.isGroup = true
        MessagesInboxStore.shared.replaceConversations([top, group])

        let outgoing = makeMessage(
            id: "m-group-out",
            conversationID: group.id,
            body: "group send",
            at: 600
        )
        MessagesInboxStore.shared.patchFromMessage(
            outgoing,
            viewerID: viewer,
            policy: .confirmedOutgoing,
            fallbackConversation: group
        )

        XCTAssertEqual(MessagesInboxStore.shared.visibleConversations.first?.id, group.id)
        XCTAssertEqual(MessagesInboxStore.shared.visibleConversations.first?.lastMessagePreview, "group send")
    }

    func testDenormalizedServerPatchDoesNotDowngradeConfirmedOutgoing() {
        let conversation = makeConversation(
            id: "dm",
            preview: "outgoing latest",
            at: 400,
            messageID: "m-out"
        )
        MessagesInboxStore.shared.replaceConversations([conversation])

        var staleServer = conversation
        staleServer.lastMessagePreview = "stale incoming"
        staleServer.lastMessageAt = Date(timeIntervalSince1970: 100)
        staleServer.lastMessageID = MessageID("m-stale")
        MessagesInboxStore.shared.patchFromServerConversation(staleServer)

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(row.lastMessagePreview, "outgoing latest")
        XCTAssertEqual(row.lastMessageID, MessageID("m-out"))
    }

    func testAlternatingSendersProduceDeterministicOrder() {
        let conversation = makeConversation(
            id: "dm",
            preview: "a",
            at: 100,
            messageID: "m1"
        )
        MessagesInboxStore.shared.replaceConversations([conversation])

        let outgoing = makeMessage(id: "m2", conversationID: conversation.id, body: "B", at: 200)
        MessagesInboxStore.shared.patchFromMessage(
            outgoing,
            viewerID: viewer,
            policy: .confirmedOutgoing,
            fallbackConversation: conversation
        )
        let incoming = makeMessage(
            id: "m3",
            conversationID: conversation.id,
            sender: peer,
            body: "C",
            at: 300
        )
        MessagesInboxStore.shared.patchFromMessage(incoming, viewerID: viewer, conversationOpen: false)
        let outgoingAgain = makeMessage(id: "m4", conversationID: conversation.id, body: "D", at: 400)
        MessagesInboxStore.shared.patchFromMessage(
            outgoingAgain,
            viewerID: viewer,
            policy: .confirmedOutgoing,
            fallbackConversation: conversation
        )

        let row = MessagesInboxStore.shared.conversations.first { $0.id == conversation.id }!
        XCTAssertEqual(row.lastMessagePreview, "D")
        XCTAssertEqual(row.lastMessageID, MessageID("m4"))
    }

    // MARK: - Helpers

    private func makeConversation(
        id: String,
        preview: String,
        at: TimeInterval,
        messageID: String
    ) -> Conversation {
        Conversation(
            id: ConversationID(id),
            participantProfileIDs: [viewer, peer],
            title: id,
            peerUsername: id,
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: preview,
            lastMessageAt: Date(timeIntervalSince1970: at),
            lastMessageID: MessageID(messageID),
            unreadCount: 0,
            isMuted: false,
            updatedAt: Date(timeIntervalSince1970: at)
        )
    }

    private func makeDirectConversation(
        id: ConversationID,
        participants: [ProfileID]
    ) -> Conversation {
        Conversation(
            id: id,
            participantProfileIDs: participants,
            title: "DM",
            peerUsername: "peer",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            unreadCount: 0,
            isMuted: false,
            updatedAt: .now
        )
    }

    private func makeMessage(
        id: String,
        conversationID: ConversationID,
        sender: ProfileID? = nil,
        body: String,
        at: TimeInterval
    ) -> Message {
        Message(
            id: MessageID(id),
            conversationID: conversationID,
            senderProfileID: sender ?? viewer,
            kind: .text,
            body: body,
            attachments: [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: at),
            isReadByViewer: true
        )
    }
}
