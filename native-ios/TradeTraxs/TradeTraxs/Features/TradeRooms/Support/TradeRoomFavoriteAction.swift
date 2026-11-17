import Foundation

enum TradeRoomFavoriteAction {
    @MainActor
    static func toggle(
        roomID: RoomID,
        viewerID: ProfileID,
        rooms: any RoomRepository,
        favoritesStore: TradeRoomFavoritesStore? = nil
    ) async -> Bool {
        let favoritesStore = favoritesStore ?? TradeRoomFavoritesStore.shared
        let nextFavorited = !favoritesStore.isFavorited(roomID)
        favoritesStore.setFavorited(roomID, favorited: nextFavorited)
        ExperienceHaptics.play(.selection)
        do {
            try await rooms.setRoomFavorited(
                roomID: roomID,
                profileID: viewerID,
                favorited: nextFavorited
            )
            return true
        } catch {
            favoritesStore.setFavorited(roomID, favorited: !nextFavorited)
            return false
        }
    }

    @MainActor
    static func hydrateIfNeeded(
        viewerID: ProfileID,
        rooms: any RoomRepository,
        favoritesStore: TradeRoomFavoritesStore? = nil
    ) async {
        let favoritesStore = favoritesStore ?? TradeRoomFavoritesStore.shared
        guard favoritesStore.allFavoriteRoomIDs.isEmpty else { return }
        do {
            let ids = try await rooms.favoritedRoomIDs(for: viewerID)
            favoritesStore.patchFromServer(roomIDs: ids)
        } catch {
            // Non-fatal — optimistic UI still works per-room after toggle.
        }
    }
}