import Foundation

/// Owner-only Trade Room management — extends base ``RoomRepository`` without breaking test stubs.
nonisolated protocol RoomManagementRepository: RoomRepository, Sendable {
    func updateRoom(roomID: RoomID, request: RoomUpdateRequest) async throws -> TradeRoom
    func createChannel(roomID: RoomID, request: RoomChannelCreateRequest) async throws -> RoomChannel
    func updateChannel(channelID: RoomChannelID, request: RoomChannelUpdateRequest) async throws -> RoomChannel
    func deleteChannel(roomID: RoomID, channelID: RoomChannelID, channelName: String) async throws
    func channelMessageCount(roomID: RoomID, channelID: RoomChannelID, channelName: String) async throws -> Int
    func managedMembers(roomID: RoomID, ownerProfileID: ProfileID) async throws -> [RoomManagedMember]
    func bannedMembers(roomID: RoomID) async throws -> [RoomBanRecord]
    func removeMember(roomID: RoomID, profileID: ProfileID) async throws
    func banMember(roomID: RoomID, profileID: ProfileID, bannedBy: ProfileID) async throws
    func unbanMember(roomID: RoomID, banID: String) async throws
    func ensureDefaultMemberTags(roomID: RoomID) async throws
    func memberTags(roomID: RoomID) async throws -> [RoomMemberTag]
    func createMemberTag(
        roomID: RoomID,
        name: String,
        colorKey: String,
        createdBy: ProfileID
    ) async throws -> RoomMemberTag
    func updateMemberTag(_ tag: RoomMemberTag) async throws -> RoomMemberTag
    func deleteMemberTag(tagID: RoomMemberTagID, roomID: RoomID) async throws
    func memberTagAssignments(roomID: RoomID) async throws -> [RoomMemberTagAssignment]
    func assignMemberTag(roomID: RoomID, profileID: ProfileID, tagID: RoomMemberTagID) async throws
    func removeMemberTagAssignment(
        roomID: RoomID,
        profileID: ProfileID,
        tagID: RoomMemberTagID
    ) async throws
    /// Owner — `rpc_v1_list_trade_room_join_requests`.
    func pendingJoinRequests(roomID: RoomID) async throws -> [RoomJoinRequestRecord]
    /// Owner — `rpc_v1_resolve_trade_room_join_request`.
    func resolveJoinRequest(requestID: String, action: TradeRoomJoinRequestResolution) async throws
    /// Owner-only — deletes `rooms` row; RLS `rooms_delete_owner` enforces `auth.uid()`.
    func deleteRoom(roomID: RoomID) async throws
}

extension RoomManagementRepository {
    func pendingJoinRequests(roomID: RoomID) async throws -> [RoomJoinRequestRecord] { [] }

    func resolveJoinRequest(
        requestID: String,
        action: TradeRoomJoinRequestResolution
    ) async throws {
        throw DomainError.businessRule(.message("Join request management is not supported by this repository."))
    }

    func deleteRoom(roomID: RoomID) async throws {
        throw DomainError.businessRule(.message("Delete room is not supported by this repository."))
    }
}
