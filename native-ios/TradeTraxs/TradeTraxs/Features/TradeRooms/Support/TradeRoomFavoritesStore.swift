import Foundation
import Observation

/// Viewer-scoped Trade Room favorites, backed by `room_members.is_favorited`.
@MainActor
@Observable
final class TradeRoomFavoritesStore {
    static let shared = TradeRoomFavoritesStore()

    private var favoriteRoomIDs: Set<RoomID> = []
    private(set) var revision: UInt64 = 0

    func isFavorited(_ roomID: RoomID) -> Bool {
        favoriteRoomIDs.contains(roomID)
    }

    func replaceAll(_ roomIDs: Set<RoomID>) {
        guard favoriteRoomIDs != roomIDs else { return }
        favoriteRoomIDs = roomIDs
        bumpRevision()
    }

    func setFavorited(_ roomID: RoomID, favorited: Bool) {
        if favorited {
            guard favoriteRoomIDs.insert(roomID).inserted else { return }
        } else {
            guard favoriteRoomIDs.remove(roomID) != nil else { return }
        }
        bumpRevision()
        NotificationCenter.default.post(name: .tradeRoomFavoriteDidChange, object: roomID)
    }

    func patchFromServer(roomIDs: some Sequence<RoomID>) {
        replaceAll(Set(roomIDs))
    }

    func resetForTesting() {
        favoriteRoomIDs = []
        revision = 0
    }

    var allFavoriteRoomIDs: Set<RoomID> {
        favoriteRoomIDs
    }

    private func bumpRevision() {
        revision &+= 1
    }
}