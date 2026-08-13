import Foundation
import Observation

/// Session-scoped Explore state so Feed → Explore → Profile → Back does not cold-reload.
@Observable
@MainActor
final class ExploreSessionStore {
    static let shared = ExploreSessionStore()

    private(set) var suggestedTraders: [ExploreTraderSuggestion] = []
    private(set) var popularRooms: [ExploreRoomSuggestion] = []
    private(set) var viewerFollowingIDs: Set<ProfileID> = []
    private(set) var hasBootstrapped = false
    private(set) var tradersNextCursor: String?
    private(set) var tradersFailedMessage: String?
    private(set) var roomsFailedMessage: String?

    private init() {}

    func applyBootstrap(
        traders: [ExploreTraderSuggestion],
        rooms: [ExploreRoomSuggestion],
        following: Set<ProfileID>,
        tradersNextCursor: String?,
        clearFailures: Bool = true
    ) {
        suggestedTraders = traders
        popularRooms = rooms
        viewerFollowingIDs = following
        self.tradersNextCursor = tradersNextCursor
        if clearFailures {
            tradersFailedMessage = nil
            roomsFailedMessage = nil
        }
        hasBootstrapped = true
    }

    func updateFollowing(_ following: Set<ProfileID>) {
        viewerFollowingIDs = following
        suggestedTraders = suggestedTraders.filter { !following.contains($0.id) }
    }

    func appendTraders(_ traders: [ExploreTraderSuggestion], nextCursor: String?) {
        let existing = Set(suggestedTraders.map(\.id))
        suggestedTraders.append(contentsOf: traders.filter { !existing.contains($0.id) })
        tradersNextCursor = nextCursor
    }

    func setTradersFailed(_ message: String) {
        tradersFailedMessage = message
        if suggestedTraders.isEmpty {
            hasBootstrapped = true
        }
    }

    func setRoomsFailed(_ message: String) {
        roomsFailedMessage = message
    }

    func setFollowing(_ id: ProfileID, isFollowing: Bool) {
        if isFollowing {
            viewerFollowingIDs.insert(id)
        } else {
            viewerFollowingIDs.remove(id)
        }
    }

    func invalidate() {
        suggestedTraders = []
        popularRooms = []
        viewerFollowingIDs = []
        hasBootstrapped = false
        tradersNextCursor = nil
        tradersFailedMessage = nil
        roomsFailedMessage = nil
    }
}
