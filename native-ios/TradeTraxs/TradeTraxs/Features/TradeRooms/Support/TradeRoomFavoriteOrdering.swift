import Foundation

enum TradeRoomFavoriteOrdering {
    /// Owned rooms first, then joined; favorited rooms first within each group; stable otherwise.
    static func orderedForSwitcher(
        _ rooms: [ExploreRoomSuggestion],
        viewerID: ProfileID,
        favoriteRoomIDs: Set<RoomID>
    ) -> [ExploreRoomSuggestion] {
        guard !rooms.isEmpty else { return [] }
        var ownedFavorites: [ExploreRoomSuggestion] = []
        var ownedOther: [ExploreRoomSuggestion] = []
        var joinedFavorites: [ExploreRoomSuggestion] = []
        var joinedOther: [ExploreRoomSuggestion] = []
        for room in rooms {
            let owned = room.ownerProfileID == viewerID || room.viewerIsOwner
            let favorited = favoriteRoomIDs.contains(room.id) || room.viewerIsFavorited
            if owned {
                if favorited { ownedFavorites.append(room) } else { ownedOther.append(room) }
            } else if favorited {
                joinedFavorites.append(room)
            } else {
                joinedOther.append(room)
            }
        }
        return ownedFavorites + ownedOther + joinedFavorites + joinedOther
    }
}