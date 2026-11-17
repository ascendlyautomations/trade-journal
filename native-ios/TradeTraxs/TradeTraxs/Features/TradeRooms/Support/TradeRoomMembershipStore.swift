import Foundation
import Observation

/// Viewer-scoped Trade Room membership — optimistic joins mirror ``TradeRoomFavoritesStore``.
@MainActor
@Observable
final class TradeRoomMembershipStore {
    static let shared = TradeRoomMembershipStore()

    private var joinedRoomIDs: Set<RoomID> = []
    /// Optimistic leaves — stale bootstrap must not mark the room joined again until the server agrees.
    private var pendingLeaveRoomIDs: Set<RoomID> = []
    private(set) var revision: UInt64 = 0

    func isJoined(_ roomID: RoomID) -> Bool {
        joinedRoomIDs.contains(roomID)
    }

    var allJoinedRoomIDs: Set<RoomID> {
        joinedRoomIDs
    }

    func setJoined(_ roomID: RoomID, joined: Bool) {
        if joined {
            pendingLeaveRoomIDs.remove(roomID)
            guard joinedRoomIDs.insert(roomID).inserted else { return }
        } else {
            let removed = joinedRoomIDs.remove(roomID) != nil
            let alreadyPendingLeave = pendingLeaveRoomIDs.contains(roomID)
            pendingLeaveRoomIDs.insert(roomID)
            guard removed || !alreadyPendingLeave else { return }
        }
        bumpRevision()
        NotificationCenter.default.post(
            name: .tradeRoomMembershipDidChange,
            object: roomID,
            userInfo: [TradeRoomNotificationKey.membershipJoined: joined]
        )
    }

      /// Server bootstrap / inbox — union optimistic joins; honor optimistic leaves over stale server rows.
    func mergeServerMembership(_ roomIDs: Set<RoomID>) {
        for pendingLeave in pendingLeaveRoomIDs where !roomIDs.contains(pendingLeave) {
            pendingLeaveRoomIDs.remove(pendingLeave)
        }
        let optimisticJoins = joinedRoomIDs.subtracting(roomIDs).subtracting(pendingLeaveRoomIDs)
        let merged = roomIDs.union(optimisticJoins).subtracting(pendingLeaveRoomIDs)
        guard merged != joinedRoomIDs else { return }
        joinedRoomIDs = merged
        bumpRevision()
        NotificationCenter.default.post(name: .tradeRoomMembershipDidChange, object: nil)
    }

    func replaceAll(_ roomIDs: Set<RoomID>) {
        guard joinedRoomIDs != roomIDs else { return }
        joinedRoomIDs = roomIDs
        bumpRevision()
        NotificationCenter.default.post(name: .tradeRoomMembershipDidChange, object: nil)
    }

    func resetForTesting() {
        joinedRoomIDs = []
        pendingLeaveRoomIDs = []
        revision = 0
    }

    private func bumpRevision() {
        revision &+= 1
    }
}