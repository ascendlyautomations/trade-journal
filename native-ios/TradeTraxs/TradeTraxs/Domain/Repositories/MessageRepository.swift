import Foundation

/// Inbox bootstrap — conversations plus profiles already embedded in the PostgREST join.
nonisolated struct ConversationListResult: Sendable {
    var items: [Conversation]
    var nextCursor: String?
    /// Participant profiles from `conversation_participants.profiles(...)` — seed session cache.
    var embeddedProfiles: [Profile]

    var page: CursorPage<Conversation> {
        CursorPage(items: items, nextCursor: nextCursor)
    }
}

nonisolated protocol MessageRepository: Sendable {
    /// Inbox list — web `fetchUserDmConversations` + unread/mute pipeline.
    func conversations(page: PageRequest) async throws -> ConversationListResult
    func conversation(id: ConversationID) async throws -> Conversation
    func messages(
        in conversationID: ConversationID,
        page: PageRequest
    ) async throws -> CursorPage<Message>
    func send(_ message: Message) async throws -> Message
    /// Web `mark_conversation_read(p_conversation_id)` — no extra parameters.
    func markRead(conversationID: ConversationID) async throws
    /// Web `mark_conversation_unread(p_conversation_id)`.
    func markUnread(conversationID: ConversationID) async throws
    /// Web `ensureDmConversation` — find existing 1:1 or create shell + participants.
    func createConversation(participantIDs: [ProfileID]) async throws -> Conversation
    /// Targeted duplicate DM lookup — used by creation coordinator after local inbox scan.
    func findExistingDirectConversationID(
        viewerID: ProfileID,
        recipientID: ProfileID
    ) async throws -> ConversationID?
    /// Block check for DM/group creation — `users_have_active_block`.
    func usersHaveActiveBlock(viewerID: ProfileID, otherID: ProfileID) async -> Bool
    /// Create 1:1 shell + participants; returns domain from known profile without refetch.
    func createDirectConversation(viewerID: ProfileID, recipient: Profile) async throws -> Conversation
    /// Create group shell + participants; returns domain from known profiles without refetch.
    func createGroupConversation(
        viewerID: ProfileID,
        recipients: [Profile],
        name: String?
    ) async throws -> Conversation
    /// Web messages `handleDeleteConversation` — delete own `conversation_participants` row.
    func deleteConversation(id: ConversationID) async throws
    /// Web `deleteForEveryone` — soft-delete own DM (`messages.deleted_for_everyone = true`).
    func deleteMessageForEveryone(_ messageID: MessageID, in conversationID: ConversationID) async throws
    /// Web `setConversationNotificationsEnabled` — per-user mute via `conversation_member_preferences`.
    func setConversationNotificationsEnabled(
        conversationID: ConversationID,
        enabled: Bool
    ) async throws
    /// Web `get_dm_block_status`.
    func fetchDmBlockStatus(conversationID: ConversationID) async throws -> DmBlockStatus
    /// Web `get_user_block_status`.
    func fetchUserBlockStatus(otherID: ProfileID) async throws -> DmBlockStatus
    /// Web `set_dm_user_block`.
    func setDmUserBlock(conversationID: ConversationID, blocked: Bool) async throws -> DmBlockStatus
    /// Profile-level block without an existing conversation — `set_user_block`.
    func setUserBlock(otherID: ProfileID, blocked: Bool) async throws -> DmBlockStatus
    /// Blocked accounts list — `user_blocks` + embedded profiles (RLS: own rows).
    func fetchBlockedAccounts() async throws -> [BlockedAccount]
    /// Muted 1:1 peers — `list_muted_dm_peers`.
    func fetchMutedDirectMessagePeers() async throws -> [MutedDirectMessagePeer]
}

extension MessageRepository {
    func fetchDmBlockStatus(conversationID: ConversationID) async throws -> DmBlockStatus {
        throw AppError.notImplemented(feature: "fetchDmBlockStatus")
    }

    func fetchUserBlockStatus(otherID: ProfileID) async throws -> DmBlockStatus {
        throw AppError.notImplemented(feature: "fetchUserBlockStatus")
    }

    func setDmUserBlock(conversationID: ConversationID, blocked: Bool) async throws -> DmBlockStatus {
        throw AppError.notImplemented(feature: "setDmUserBlock")
    }

    func setUserBlock(otherID: ProfileID, blocked: Bool) async throws -> DmBlockStatus {
        throw AppError.notImplemented(feature: "setUserBlock")
    }

    func fetchBlockedAccounts() async throws -> [BlockedAccount] {
        throw AppError.notImplemented(feature: "fetchBlockedAccounts")
    }

    func fetchMutedDirectMessagePeers() async throws -> [MutedDirectMessagePeer] {
        throw AppError.notImplemented(feature: "fetchMutedDirectMessagePeers")
    }
}
