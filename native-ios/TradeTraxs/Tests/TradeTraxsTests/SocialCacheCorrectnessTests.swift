import XCTest
@testable import TradeTraxs

@MainActor
final class SocialCacheCorrectnessTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let conversationID = ConversationID("cccccccc-cccc-cccc-cccc-cccccccccccc")

    override func tearDown() {
        SocialPersistedCacheCoordinator.clearAll()
        MessagesInboxStore.shared.resetForTesting()
        ActivityInboxStore.shared.resetForTesting()
        SessionMemberRoomsStore.shared.invalidate()
        ConversationThreadSessionStore.shared.invalidate()
        super.tearDown()
    }

    func testInboxPersistsAndHydratesAcrossRelaunch() {
        let peer = ProfileID("dddddddd-dddd-dddd-dddd-dddddddddddd")
        let conversation = Conversation(
            id: conversationID,
            participantProfileIDs: [viewerA, peer],
            title: "Peer",
            peerUsername: "peer",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "hello",
            lastMessageAt: .now,
            lastMessageID: MessageID("msg-1"),
            unreadCount: 2,
            isMuted: false,
            updatedAt: .now
        )
        MessagesInboxStore.shared.setPersistedViewerID(viewerA)
        MessagesInboxStore.shared.replaceConversations([conversation])

        MessagesInboxStore.shared.resetForTesting()
        XCTAssertFalse(MessagesInboxStore.shared.hasLoaded)

        XCTAssertTrue(
            SocialPersistedCacheCoordinator.hydrateInbox(
                viewerID: viewerA,
                inboxStore: MessagesInboxStore.shared
            )
        )
        XCTAssertTrue(MessagesInboxStore.shared.hasLoaded)
        XCTAssertEqual(MessagesInboxStore.shared.conversations.count, 1)
        XCTAssertEqual(MessagesInboxStore.shared.conversations.first?.lastMessagePreview, "hello")
    }

    func testDMThreadPersistsAndRestoresFromDisk() {
        let peer = ProfileID("dddddddd-dddd-dddd-dddd-dddddddddddd")
        let conversation = Conversation(
            id: conversationID,
            participantProfileIDs: [viewerA, peer],
            title: "Peer",
            peerUsername: "peer",
            avatar: nil,
            isGroup: false,
            isPinned: false,
            lastMessagePreview: "hello",
            lastMessageAt: .now,
            lastMessageID: MessageID("msg-1"),
            unreadCount: 0,
            isMuted: false,
            updatedAt: .now
        )
        let message = Message(
            id: MessageID("msg-1"),
            conversationID: conversationID,
            senderProfileID: peer,
            kind: .text,
            body: "hello",
            attachments: [],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        ConversationThreadSessionStore.shared.syncOpenThreadState(
            viewerID: viewerA,
            conversationID: conversationID,
            conversation: conversation,
            messages: [message],
            nextCursor: nil,
            hasMoreMessages: false
        )

        ConversationThreadSessionStore.shared.invalidate()
        let key = ConversationThreadSessionStore.cacheKey(viewerID: viewerA, conversationID: conversationID)
        let restored = ConversationThreadSessionStore.shared.restore(key: key)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.messages.count, 1)
        XCTAssertEqual(restored?.messages.first?.body, "hello")
    }

    func testActivityPersistsAndHydrates() {
        let notification = ActivityNotification(
            id: NotificationID("notif-1"),
            kind: .like,
            actorProfileID: ProfileID("dddddddd-dddd-dddd-dddd-dddddddddddd"),
            title: "like",
            body: "liked your post",
            tradeID: nil,
            postID: nil,
            profilePostID: nil,
            achievementPostID: nil,
            reelID: nil,
            commentID: nil,
            conversationID: nil,
            roomID: nil,
            roomMessageID: nil,
            followRequestID: nil,
            joinRequestID: nil,
            joinRequestStatus: nil,
            roomSlug: nil,
            roomName: nil,
            sectionID: nil,
            sectionName: nil,
            messagePreview: nil,
            reportID: nil,
            affiliateHref: nil,
            isReply: false,
            isMention: false,
            createdAt: .now,
            isRead: false
        )
        SocialDiskCache.saveActivity(
            SocialDiskCache.ActivityBlob(
                viewerID: viewerA.rawValue,
                savedAt: .now,
                items: [notification],
                unreadCount: 1,
                pendingFollowRequestCount: 0,
                nextCursor: nil
            )
        )
        ActivityInboxStore.shared.resetForTesting()

        XCTAssertTrue(
            SocialPersistedCacheCoordinator.hydrateActivity(viewerID: viewerA, store: ActivityInboxStore.shared)
        )
        XCTAssertTrue(ActivityInboxStore.shared.hasLoaded)
        XCTAssertEqual(ActivityInboxStore.shared.items.count, 1)
    }

    func testActivityCatchUpMergeDoesNotDuplicate() {
        let base = ActivityNotification(
            id: NotificationID("notif-1"),
            kind: .like,
            actorProfileID: ProfileID("dddddddd-dddd-dddd-dddd-dddddddddddd"),
            title: "like",
            body: "liked your post",
            tradeID: nil,
            postID: nil,
            profilePostID: nil,
            achievementPostID: nil,
            reelID: nil,
            commentID: nil,
            conversationID: nil,
            roomID: nil,
            roomMessageID: nil,
            followRequestID: nil,
            joinRequestID: nil,
            joinRequestStatus: nil,
            roomSlug: nil,
            roomName: nil,
            sectionID: nil,
            sectionName: nil,
            messagePreview: nil,
            reportID: nil,
            affiliateHref: nil,
            isReply: false,
            isMention: false,
            createdAt: .now,
            isRead: false
        )
        ActivityInboxStore.shared.replace(items: [base], unreadCount: 1, nextCursor: nil)
        ActivityInboxStore.shared.mergeCatchUp(items: [base], unreadCount: 1)
        XCTAssertEqual(ActivityInboxStore.shared.items.count, 1)
    }

    func testSessionIsolationClearsViewerASocialCacheBeforeViewerB() {
        MessagesInboxStore.shared.setPersistedViewerID(viewerA)
        MessagesInboxStore.shared.replaceConversations([
            Conversation(
                id: conversationID,
                participantProfileIDs: [viewerA, ProfileID("dddddddd-dddd-dddd-dddd-dddddddddddd")],
                title: "Secret",
                peerUsername: "peer",
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: "secret",
                lastMessageAt: .now,
                lastMessageID: MessageID("msg-secret"),
                unreadCount: 1,
                isMuted: false,
                updatedAt: .now
            )
        ])

        SocialPersistedCacheCoordinator.clearAll()
        MessagesInboxStore.shared.resetForTesting()

        XCTAssertFalse(
            SocialPersistedCacheCoordinator.hydrateInbox(
                viewerID: viewerB,
                inboxStore: MessagesInboxStore.shared
            )
        )
        XCTAssertTrue(MessagesInboxStore.shared.conversations.isEmpty)
    }
}
