import Foundation

/// Aligns optimistic join/inbox hints with active `room_members` rows (`left_at IS NULL`).
@MainActor
enum TradeRoomStaleMembershipReconciler {
    /// Returns `true` when the viewer has an active server membership row.
    @discardableResult
    static func reconcileOptimisticJoinState(
        roomID: RoomID,
        viewerID: ProfileID,
        rooms: any RoomRepository,
        inboxStore: MessagesInboxStore
    ) async -> Bool {
        if let active = try? await rooms.membership(roomID: roomID, profileID: viewerID) {
            TradeRoomConfirmedMembershipCache.store(active, for: roomID)
            TradeRoomMembershipStore.shared.setJoined(roomID, joined: true)
            return true
        }

        TradeRoomConfirmedMembershipCache.clear(for: roomID)

        let hadOptimisticJoin = TradeRoomMembershipStore.shared.isJoined(roomID)
            || inboxStore.rooms.contains { $0.id == roomID }
        if TradeRoomMembershipStore.shared.isJoined(roomID) {
            TradeRoomMembershipStore.shared.setJoined(roomID, joined: false)
        }
        if inboxStore.rooms.contains(where: { $0.id == roomID }) {
            inboxStore.removeRoom(id: roomID)
            SessionMemberRoomsStore.shared.removeMemberRoom(roomID, for: viewerID)
        }
        if hadOptimisticJoin || TradeRoomJoinActionCoordinator.shared.mutationStates[roomID] != nil {
            TradeRoomJoinActionCoordinator.shared.clearMutation(for: roomID)
        }
        return false
    }
}