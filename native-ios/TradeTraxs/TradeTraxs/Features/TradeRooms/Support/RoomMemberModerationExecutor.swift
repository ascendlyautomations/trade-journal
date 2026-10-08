import Foundation

/// Persists ban/remove through ``RoomManagementRepository`` and syncs member counts.
enum RoomMemberModerationExecutor {
    static func removeMember(
        roomID: RoomID,
        profileID: ProfileID,
        rooms: any RoomRepository,
        inboxStore: MessagesInboxStore,
        viewerID: ProfileID
    ) async throws {
        guard let management = rooms as? any RoomManagementRepository else { return }
        try await management.removeMember(roomID: roomID, profileID: profileID)
        try await syncMemberCount(roomID: roomID, rooms: rooms, inboxStore: inboxStore, viewerID: viewerID)
    }

    static func banMember(
        roomID: RoomID,
        profileID: ProfileID,
        bannedBy: ProfileID,
        rooms: any RoomRepository,
        inboxStore: MessagesInboxStore,
        viewerID: ProfileID
    ) async throws {
        guard let management = rooms as? any RoomManagementRepository else { return }
        try await management.banMember(roomID: roomID, profileID: profileID, bannedBy: bannedBy)
        try await syncMemberCount(roomID: roomID, rooms: rooms, inboxStore: inboxStore, viewerID: viewerID)
    }

    private static func syncMemberCount(
        roomID: RoomID,
        rooms: any RoomRepository,
        inboxStore: MessagesInboxStore,
        viewerID: ProfileID
    ) async throws {
        let activeCount = (try await rooms.activeMemberCounts(for: [roomID]))[roomID]
        if let activeCount {
            RoomMemberCountSync.apply(
                roomID: roomID,
                count: activeCount,
                inboxStore: inboxStore,
                viewerID: viewerID
            )
        }
    }
}
