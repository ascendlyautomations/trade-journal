import Foundation

@MainActor
enum TradeRoomFavoriteSync {
    static func applyFavoritedFlag(
        to rooms: [ExploreRoomSuggestion],
        store: TradeRoomFavoritesStore? = nil
    ) -> [ExploreRoomSuggestion] {
        let store = store ?? TradeRoomFavoritesStore.shared
        return rooms.map { room in
            var copy = room
            copy.isFavorited = store.isFavorited(room.id) || room.isFavorited == true
            return copy
        }
    }

    static func patch(
        _ room: ExploreRoomSuggestion,
        store: TradeRoomFavoritesStore? = nil
    ) -> ExploreRoomSuggestion {
        let store = store ?? TradeRoomFavoritesStore.shared
        var copy = room
        copy.isFavorited = store.isFavorited(room.id) || room.isFavorited == true
        return copy
    }
}