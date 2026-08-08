import Foundation

nonisolated protocol RoomRepository: Sendable {
    func room(id: RoomID) async throws -> TradeRoom
    func rooms(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<TradeRoom>
    func membership(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership?
    func join(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership
    func leave(roomID: RoomID, profileID: ProfileID) async throws
    func messages(roomID: RoomID, page: PageRequest) async throws -> CursorPage<RoomMessage>
    func send(_ message: RoomMessage) async throws -> RoomMessage
    func moderate(
        roomID: RoomID,
        messageID: RoomMessageID?,
        targetProfileID: ProfileID?,
        action: RoomModerationAction
    ) async throws
}
