import Foundation

/// Your Rooms list for in-room switcher — same sources as Trade Rooms home bootstrap.
@MainActor
enum TradeRoomYourRoomsCatalog {
    static func rooms(viewerID: ProfileID?) -> [ExploreRoomSuggestion] {
        guard let viewerID else { return [] }
        return orderOwnedFirstForSwitcher(unorderedRooms(viewerID: viewerID), viewerID: viewerID)
    }

    /// Owned rooms first, then joined-only; stable order within each group (nav switcher).
    static func orderOwnedFirstForSwitcher(
        _ rooms: [ExploreRoomSuggestion],
        viewerID: ProfileID
    ) -> [ExploreRoomSuggestion] {
        TradeRoomFavoriteOrdering.orderedForSwitcher(
            TradeRoomFavoriteSync.applyFavoritedFlag(to: rooms),
            viewerID: viewerID,
            favoriteRoomIDs: TradeRoomFavoritesStore.shared.allFavoriteRoomIDs
        )
    }

    private static func unorderedRooms(viewerID: ProfileID) -> [ExploreRoomSuggestion] {
        if let bootstrap = SessionTradeRoomsDiscoveryStore.shared.cached(
            for: viewerID,
            scope: .all,
            category: nil
        ), !bootstrap.yourRooms.isEmpty {
            return bootstrap.yourRooms
        }

        let inbox = MessagesInboxStore.shared.rooms
        if !inbox.isEmpty {
            return inbox.map {
                ExploreRoomSuggestion.fromMembership(
                    room: $0,
                    ownerName: nil,
                    ownerUsername: nil,
                    viewerID: viewerID
                )
            }
        }

        if let cached = SessionMemberRoomsStore.shared.cached(for: viewerID), !cached.0.isEmpty {
            return cached.0.map {
                ExploreRoomSuggestion.fromMembership(
                    room: $0,
                    ownerName: nil,
                    ownerUsername: nil,
                    viewerID: viewerID
                )
            }
        }

        return []
    }

    static func prefetchIfNeeded(
        viewerID: ProfileID,
        explore: any ExploreRepository
    ) async {
        guard rooms(viewerID: viewerID).isEmpty else { return }
        _ = try? await SessionTradeRoomsDiscoveryStore.shared.coalesce(
            viewerID: viewerID,
            scope: .all,
            category: nil,
            forceNetwork: false
        ) {
            try await explore.tradeRoomsHomeBootstrap(scope: .all, limit: 40, suggestedCursor: nil, popularCursor: nil, category: nil)
        }
    }
}