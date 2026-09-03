import XCTest
@testable import TradeTraxs

/// Regression tests for personal DM thread reload / bootstrap / cache persistence.
@MainActor
final class ConversationThreadReloadPersistenceTests: XCTestCase {
    private let viewer = ProfileID("viewer-1")
    private let peer = ProfileID("peer-1")
    private let conversationID = ConversationID("convo-1")

    override func setUp() async throws {
        BackendV2FeatureFlags.resetFlagsForTests()
        ConversationThreadSessionStore.shared.invalidate()
        MessagesInboxStore.shared.resetForTesting()
        await BackendV2SingleFlight.shared.clear()
        await BackendV2RpcAvailability.shared.clear()
    }

    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        ConversationThreadSessionStore.shared.invalidate()
        MessagesInboxStore.shared.resetForTesting()
        Task {
            await BackendV2SingleFlight.shared.clear()
            await BackendV2RpcAvailability.shared.clear()
        }
        super.tearDown()
    }

    // MARK: - Bootstrap merge (V2)

    func testSenderAuthoredMessageSurvivesBootstrapReloadMerge() {
        let existing = [makeMessage(id: "sent-by-me", body: "unique-dm", sender: viewer, at: 200)]
        let staleBootstrap = [makeMessage(id: "peer-old", body: "Hello", sender: peer, at: 100)]

        let merged = ConversationMessageMerge.mergeMessageLists(existing: existing, incoming: staleBootstrap)

        XCTAssertEqual(merged.map(\.id.rawValue), ["peer-old", "sent-by-me"])
        XCTAssertTrue(merged.contains { $0.id.rawValue == "sent-by-me" && $0.body == "unique-dm" })
    }

    func testRecipientAuthoredMessageSurvivesBootstrapReloadMerge() {
        let existing = [makeMessage(id: "peer-new", body: "incoming", sender: peer, at: 300)]
        let bootstrap = [
            makeMessage(id: "peer-old", body: "Hello", sender: peer, at: 100),
            makeMessage(id: "peer-new", body: "incoming", sender: peer, at: 300),
        ]

        let merged = ConversationMessageMerge.mergeMessageLists(existing: existing, incoming: bootstrap)

        XCTAssertEqual(merged.filter { $0.id.rawValue == "peer-new" }.count, 1)
        XCTAssertEqual(merged.last?.body, "incoming")
    }

    func testOptimisticReconcilesIntoOneConfirmedMessage() {
        let temp = makeMessage(id: "temp-send", body: "unique-dm", sender: viewer, at: 1_000)
        let confirmed = makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 1_002)

        let merged = ConversationMessageMerge.mergeMessages(
            existing: [temp],
            incoming: [confirmed],
            viewerID: viewer
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id.rawValue, "server-msg")
    }

    func testRealtimeEchoDoesNotDuplicateOrRemoveConfirmedMessage() {
        let confirmed = makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 1_000)
        let echo = makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 1_000)

        let merged = ConversationMessageMerge.mergeMessages(
            existing: [confirmed],
            incoming: [echo],
            viewerID: viewer
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id.rawValue, "server-msg")
    }

    func testLatePreSendBootstrapCannotEraseConfirmedSend() {
        let postSend = [makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 500)]
        let preSendBootstrap = [makeMessage(id: "peer-old", body: "Hello", sender: peer, at: 100)]

        let merged = ConversationMessageMerge.mergeMessageLists(existing: postSend, incoming: preSendBootstrap)

        XCTAssertTrue(merged.contains { $0.id.rawValue == "server-msg" })
        XCTAssertEqual(merged.count, 2)
    }

    func testStaleCacheCannotReplaceNewerCanonicalState() {
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: conversationID)
        let convo = makeConversation()
        let sent = makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 500)

        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: key,
                conversation: convo,
                messages: [sent],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date(),
                contentGeneration: 2
            )
        )

        ConversationThreadSessionStore.shared.saveMergedFirstPage(
            cacheKey: key,
            conversation: convo,
            incoming: [makeMessage(id: "peer-old", body: "Hello", sender: peer, at: 100)],
            nextCursor: nil,
            hasMoreMessages: false
        )

        let restored = ConversationThreadSessionStore.shared.restore(key: key)
        XCTAssertEqual(restored?.contentGeneration, 2)
        XCTAssertTrue(restored?.messages.contains { $0.id.rawValue == "server-msg" } == true)
        XCTAssertEqual(restored?.messages.count, 2)
    }

    func testPatchMessagesSurvivesLeaveAndReopenSimulation() {
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: conversationID)
        let convo = makeConversation()
        let baseline = makeMessage(id: "peer-old", body: "Hello", sender: peer, at: 100)

        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: key,
                conversation: convo,
                messages: [baseline],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date().addingTimeInterval(-5),
                contentGeneration: 1
            )
        )

        let sent = makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 200)
        ConversationThreadSessionStore.shared.patchMessages(
            viewerID: viewer,
            conversationID: conversationID,
            incoming: [sent],
            conversation: convo
        )

        let reopened = ConversationThreadSessionStore.shared.restore(key: key)
        XCTAssertNotNil(reopened)
        XCTAssertFalse(reopened?.isSoftStale == true)
        XCTAssertEqual(reopened?.messages.map(\.id.rawValue), ["peer-old", "server-msg"])
        XCTAssertEqual(reopened?.contentGeneration, 2)
    }

    func testSyncOpenThreadStatePreservesPaginatedHistoryAfterBatchDelete() {
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: conversationID)
        let convo = makeConversation()
        var paginated: [Message] = (1...60).map { index in
            makeMessage(
                id: "msg-\(index)",
                body: "body-\(index)",
                sender: index.isMultiple(of: 2) ? peer : viewer,
                at: TimeInterval(index)
            )
        }
        paginated = ConversationMessageMerge.sortByCreatedAt(paginated)

        ConversationThreadSessionStore.shared.syncOpenThreadState(
            viewerID: viewer,
            conversationID: conversationID,
            conversation: convo,
            messages: paginated,
            nextCursor: "older-cursor",
            hasMoreMessages: true
        )

        let deleteIDs: Set<String> = ["msg-10", "msg-25", "msg-55"]
        let afterDelete = paginated.filter { !deleteIDs.contains($0.id.rawValue) }
        ConversationThreadSessionStore.shared.syncOpenThreadState(
            viewerID: viewer,
            conversationID: conversationID,
            conversation: convo,
            messages: afterDelete,
            nextCursor: "older-cursor",
            hasMoreMessages: true
        )

        let reopened = ConversationThreadSessionStore.shared.restore(key: key)
        XCTAssertEqual(reopened?.messages.count, 57)
        XCTAssertEqual(reopened?.nextCursor, "older-cursor")
        XCTAssertTrue(reopened?.hasMoreMessages == true)
        for id in deleteIDs {
            XCTAssertFalse(reopened?.messages.contains { $0.id.rawValue == id } == true)
        }
    }

    func testSaveMergedFirstPageDoesNotTruncateExtendedThread() {
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: conversationID)
        let convo = makeConversation()
        let extended = (1...80).map { index in
            makeMessage(id: "msg-\(index)", body: "x", sender: peer, at: TimeInterval(index))
        }

        ConversationThreadSessionStore.shared.syncOpenThreadState(
            viewerID: viewer,
            conversationID: conversationID,
            conversation: convo,
            messages: extended,
            nextCursor: "cursor-80",
            hasMoreMessages: true
        )

        let serverFirstPage = (31...80).map { index in
            makeMessage(id: "msg-\(index)", body: "x", sender: peer, at: TimeInterval(index))
        }
        ConversationThreadSessionStore.shared.saveMergedFirstPage(
            cacheKey: key,
            conversation: convo,
            incoming: serverFirstPage,
            nextCursor: "cursor-80",
            hasMoreMessages: true
        )

        let restored = ConversationThreadSessionStore.shared.restore(key: key)
        XCTAssertEqual(restored?.messages.count, 80)
        XCTAssertTrue(restored?.messages.contains { $0.id.rawValue == "msg-1" } == true)
        XCTAssertTrue(restored?.messages.contains { $0.id.rawValue == "msg-30" } == true)
    }

    func testPaginationCannotRemoveNewestMessage() {
        let newest = makeMessage(id: "newest", body: "latest", sender: viewer, at: 900)
        let olderPage = [
            makeMessage(id: "old-1", body: "a", sender: peer, at: 100),
            makeMessage(id: "old-2", body: "b", sender: peer, at: 200),
        ]
        let existing = [newest]

        let merged = ConversationMessageMerge.mergeMessages(
            existing: existing,
            incoming: olderPage,
            viewerID: viewer
        )

        XCTAssertTrue(merged.contains { $0.id.rawValue == "newest" })
        XCTAssertEqual(merged.first?.id.rawValue, "old-1")
    }

    func testEqualTimestampMessagesRemainDeterministicallyOrdered() {
        let sameTime = Date(timeIntervalSince1970: 500)
        let a = Message(
            id: MessageID("b-id"),
            conversationID: conversationID,
            senderProfileID: peer,
            kind: .text,
            body: "b",
            attachments: [],
            replyToMessageID: nil,
            createdAt: sameTime,
            isReadByViewer: true
        )
        let b = Message(
            id: MessageID("a-id"),
            conversationID: conversationID,
            senderProfileID: peer,
            kind: .text,
            body: "a",
            attachments: [],
            replyToMessageID: nil,
            createdAt: sameTime,
            isReadByViewer: true
        )

        let sorted = ConversationMessageMerge.sortByCreatedAt([a, b])
        XCTAssertEqual(sorted.map(\.id.rawValue), ["a-id", "b-id"])
    }

    func testSwitchingConversationsCannotApplyWrongThreadState() {
        let otherConvo = ConversationID("convo-2")
        let keyA = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: conversationID)
        let keyB = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: otherConvo)

        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: keyA,
                conversation: makeConversation(),
                messages: [makeMessage(id: "a-msg", body: "A", sender: viewer, at: 100)],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date(),
                contentGeneration: 1
            )
        )
        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: keyB,
                conversation: makeConversation(id: otherConvo),
                messages: [makeMessage(id: "b-msg", body: "B", sender: peer, at: 100)],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date(),
                contentGeneration: 1
            )
        )

        XCTAssertEqual(
            ConversationThreadSessionStore.shared.restore(key: keyA)?.messages.first?.id.rawValue,
            "a-msg"
        )
        XCTAssertEqual(
            ConversationThreadSessionStore.shared.restore(key: keyB)?.messages.first?.id.rawValue,
            "b-msg"
        )
    }

    // MARK: - V2 loader integration

    func testV2BootstrapApplierMapsSenderAuthoredRow() throws {
        let json = ConversationThreadContractFixtures.directOpen.replacingOccurrences(
            of: "\"sender_id\":\"peer-1\"",
            with: "\"sender_id\":\"viewer-1\""
        )
        let bootstrap: ConversationThreadBootstrapV1 = try decode(json)
        let applied = try ConversationThreadBootstrapApplier.apply(
            bootstrap,
            conversationID: conversationID,
            viewerID: viewer,
            detailCache: DetailPresentationCache()
        )
        XCTAssertEqual(applied.messages.count, 1)
        XCTAssertEqual(applied.messages.first?.senderProfileID, viewer)
    }

    @MainActor
    func testV2FreshCacheSkipsNetworkButRetainsPatchedSend() async throws {
        BackendV2FeatureFlags.setFlagForTests(.messageThreads, enabled: true)
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewer, conversationID: conversationID)
        let convo = makeConversation()
        let baseline = makeMessage(id: "peer-old", body: "Hello", sender: peer, at: 100)

        ConversationThreadSessionStore.shared.save(
            ConversationThreadSessionStore.Snapshot(
                cacheKey: key,
                conversation: convo,
                messages: [baseline],
                nextCursor: nil,
                hasMoreMessages: false,
                loadedAt: Date(),
                contentGeneration: 1
            )
        )
        ConversationThreadSessionStore.shared.patchMessages(
            viewerID: viewer,
            conversationID: conversationID,
            incoming: [makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 200)],
            conversation: convo
        )

        let rpc = CapturingThreadRPCClient(json: ConversationThreadContractFixtures.directOpen)
        let result = try await ConversationThreadBootstrapLoader.load(
            viewerID: viewer,
            conversationID: conversationID,
            cursor: nil,
            markRead: false,
            intent: .cacheRevalidation,
            rpc: rpc,
            detailCache: DetailPresentationCache(),
            inboxStore: MessagesInboxStore.shared,
            loadGeneration: 1,
            currentGeneration: { 1 },
            forceNetwork: false
        )

        XCTAssertTrue(result.cacheHit)
        XCTAssertEqual(rpc.callCount, 0)
        XCTAssertTrue(result.applied.messages.contains { $0.id.rawValue == "server-msg" })
    }

    // MARK: - Legacy path (flag off)

    func testLegacyInitialLoadReplaceIncludesSenderMessage() {
        BackendV2FeatureFlags.resetFlagsForTests()
        let page = [
            makeMessage(id: "peer-old", body: "Hello", sender: peer, at: 100),
            makeMessage(id: "server-msg", body: "unique-dm", sender: viewer, at: 200),
        ]

        let loaded = ConversationMessageMerge.mergeMessages(existing: [], incoming: page, viewerID: viewer)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.contains { $0.senderProfileID == viewer && $0.body == "unique-dm" })
    }

    // MARK: - Helpers

    private func makeConversation(id: ConversationID? = nil) -> Conversation {
        Conversation(
            id: id ?? conversationID,
            participantProfileIDs: [viewer, peer],
            title: nil,
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
        body: String,
        sender: ProfileID,
        at: TimeInterval
    ) -> Message {
        Message(
            id: MessageID(id),
            conversationID: conversationID,
            senderProfileID: sender,
            kind: .text,
            body: body,
            attachments: [],
            replyToMessageID: nil,
            createdAt: Date(timeIntervalSince1970: at),
            isReadByViewer: true
        )
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
