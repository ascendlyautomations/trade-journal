import Foundation

nonisolated protocol RoomRepository: Sendable {
    func room(id: RoomID) async throws -> TradeRoom
    /// Rooms owned by a profile (Profile “Trade Room” CTA).
    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom>
    /// Owned room lookup — web pre-create `rooms` where `owner_user_id = user.id` limit 1.
    func ownedRoom(for profileID: ProfileID) async throws -> TradeRoom?
    /// Creates a Trade Room with default channels and owner membership (web `createUserRoom`).
    func createRoom(
        request: RoomCreateRequest,
        ownerProfileID: ProfileID,
        ownerUsername: String
    ) async throws -> TradeRoom
    /// Member rooms — web Community `loadMemberRooms` (`room_members` + embed).
    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom>
    /// Active member counts for many rooms — one `room_members` SELECT (web `loadMemberStats` parity).
    func activeMemberCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int]
    /// Active room memberships with profiles — `room_members` where `left_at IS NULL`.
    func activeMembers(roomID: RoomID, ownerProfileID: ProfileID) async throws -> [RoomManagedMember]
    /// Web `get_room_unread_counts`.
    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int]
    /// Latest `room_messages.created_at` per room — inbox card activity timestamps.
    func lastMessageActivity(for roomIDs: [RoomID]) async throws -> [RoomID: Date]
    /// Web `mark_room_read` — advances `room_members.last_read_at` / `last_read_message_id`.
    func markRead(roomID: RoomID) async throws
    /// Web `loadSections` — `room_sections` ordered by `position`.
    func channels(roomID: RoomID) async throws -> [RoomChannel]
    func membership(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership?
    func join(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership
    func leave(roomID: RoomID, profileID: ProfileID) async throws
    /// Room-wide message page (no channel filter). Prefer ``messages(roomID:channel:page:)``.
    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage>
    /// Web `fetchRoomMessages` filtered to a channel (`section_id`).
    func messages(
        roomID: RoomID,
        channel: RoomChannel?,
        page: PageRequest
    ) async throws -> CursorPage<RoomMessage>
    func send(_ message: RoomMessage) async throws -> RoomMessage
    func insertMessageReaction(
        roomID: RoomID,
        messageID: RoomMessageID,
        userID: ProfileID,
        reaction: String
    ) async throws -> RoomMessageReaction
    func deleteMessageReaction(id: String) async throws
    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws
    /// `rpc_v1_request_trade_room_join` — approval-policy rooms only.
    func requestJoin(roomID: RoomID) async throws -> TradeRoomJoinRequestState
    /// `rpc_v1_viewer_trade_room_join_request` — current viewer request row.
    func viewerJoinRequest(roomID: RoomID) async throws -> TradeRoomJoinRequestState?
}

extension RoomRepository {
    func ownedRoom(for profileID: ProfileID) async throws -> TradeRoom? {
        let page = try await rooms(for: profileID, page: PageRequest(limit: 1))
        return page.items.first
    }

    func createRoom(
        request: RoomCreateRequest,
        ownerProfileID: ProfileID,
        ownerUsername: String
    ) async throws -> TradeRoom {
        throw DomainError.businessRule(.message("Create room is not supported by this repository."))
    }

    func activeMemberCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int] { [:] }
    func lastMessageActivity(for roomIDs: [RoomID]) async throws -> [RoomID: Date] { [:] }
    func activeMembers(roomID: RoomID, ownerProfileID: ProfileID) async throws -> [RoomManagedMember] {
        []
    }

    func requestJoin(roomID: RoomID) async throws -> TradeRoomJoinRequestState {
        throw DomainError.businessRule(.message("Join requests are not supported by this repository."))
    }

    func viewerJoinRequest(roomID: RoomID) async throws -> TradeRoomJoinRequestState? {
        nil
    }
}
