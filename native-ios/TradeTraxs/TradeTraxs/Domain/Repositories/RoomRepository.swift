import Foundation

nonisolated protocol RoomRepository: Sendable {
    func room(id: RoomID) async throws -> TradeRoom
    /// Rooms owned by a profile (Profile “Trade Room” CTA).
    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom>
    /// Member rooms — web Community `loadMemberRooms` (`room_members` + embed).
    func memberRooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom>
    /// Web `get_room_unread_counts`.
    func unreadCounts(for roomIDs: [RoomID]) async throws -> [RoomID: Int]
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
    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws
}
