import Foundation

nonisolated protocol JoinRoomUseCase: Sendable {
    func execute(roomID: RoomID, profileID: ProfileID) async throws -> RoomMembership
}

nonisolated protocol LeaveRoomUseCase: Sendable {
    func execute(roomID: RoomID, profileID: ProfileID) async throws
}
