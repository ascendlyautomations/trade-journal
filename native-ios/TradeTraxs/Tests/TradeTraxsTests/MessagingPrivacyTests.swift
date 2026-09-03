import XCTest
@testable import TradeTraxs

final class MessagingPrivacyTests: XCTestCase {
    func testDmPrivacyParsesBackendValues() {
        XCTAssertEqual(DmPrivacy.parse("everyone"), .everyone)
        XCTAssertEqual(DmPrivacy.parse("following"), .following)
        XCTAssertEqual(DmPrivacy.parse("followers"), .followers)
        XCTAssertEqual(DmPrivacy.parse("mutual"), .mutual)
        XCTAssertEqual(DmPrivacy.parse("unknown"), .everyone)
    }

    func testDmBlockStatusMessagingBlocked() {
        let blocked = DmBlockStatus(
            otherUserID: ProfileID("peer"),
            blockedByMe: true,
            blockedByOther: false
        )
        XCTAssertTrue(blocked.isMessagingBlocked)

        let otherBlocked = DmBlockStatus(
            otherUserID: ProfileID("peer"),
            blockedByMe: false,
            blockedByOther: true
        )
        XCTAssertTrue(otherBlocked.isMessagingBlocked)

        let clear = DmBlockStatus(
            otherUserID: ProfileID("peer"),
            blockedByMe: false,
            blockedByOther: false
        )
        XCTAssertFalse(clear.isMessagingBlocked)
    }

    func testSettingsRouteTitlesForPrivacyLeaves() {
        XCTAssertEqual(SettingsRoute.privacyBlockedAccounts.title, "Blocked Accounts")
        XCTAssertEqual(SettingsRoute.privacyMutedAccounts.title, "Muted Accounts")
        XCTAssertEqual(SettingsRoute.privacyMessageAudience.title, "Who Can Message Me")
    }

    @MainActor
    func testUserBlockCoordinatorCachesStatus() async {
        let peerID = ProfileID("peer-1")
        let conversationID = ConversationID("convo-1")
        let inbox = MessagesInboxStore.shared
        inbox.upsertConversation(
            Conversation(
                id: conversationID,
                participantProfileIDs: [ProfileID("me"), peerID],
                title: "Peer",
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
        )

        let repo = PrivacyMessageRepositoryStub()
        repo.blockStatus = DmBlockStatus(
            otherUserID: peerID,
            blockedByMe: true,
            blockedByOther: false
        )

        _ = try? await UserBlockCoordinator.shared.setBlocked(
            otherID: peerID,
            conversationID: conversationID,
            blocked: true,
            messages: repo,
            inboxStore: inbox
        )

        XCTAssertFalse(inbox.conversations.contains { $0.id == conversationID })
        XCTAssertEqual(UserBlockCoordinator.shared.cachedStatus(for: peerID)?.blockedByMe, true)
    }
}

private final class PrivacyMessageRepositoryStub: MessageRepository, @unchecked Sendable {
    var blockStatus: DmBlockStatus?

    func conversations(page: PageRequest) async throws -> ConversationListResult {
        ConversationListResult(items: [], nextCursor: nil, embeddedProfiles: [])
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        throw AppError.notImplemented(feature: "conversation")
    }

    func messages(in conversationID: ConversationID, page: PageRequest) async throws -> CursorPage<Message> {
        CursorPage(items: [], nextCursor: nil)
    }

    func send(_ message: Message) async throws -> Message { message }

    func markRead(conversationID: ConversationID) async throws {}

    func markUnread(conversationID: ConversationID) async throws {}

    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createConversation")
    }

    func findExistingDirectConversationID(viewerID: ProfileID, recipientID: ProfileID) async throws -> ConversationID? {
        nil
    }

    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool { false }

    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createDirectConversation")
    }

    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation {
        throw AppError.notImplemented(feature: "createGroupConversation")
    }

    func deleteConversation(id: ConversationID) async throws {}

    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws {}

    func setConversationNotificationsEnabled(conversationID: ConversationID, enabled: Bool) async throws {}

    func setDmUserBlock(conversationID: ConversationID, blocked: Bool) async throws -> DmBlockStatus {
        guard let blockStatus else {
            throw AppError.unknown(message: "missing stub")
        }
        return blockStatus
    }
}
