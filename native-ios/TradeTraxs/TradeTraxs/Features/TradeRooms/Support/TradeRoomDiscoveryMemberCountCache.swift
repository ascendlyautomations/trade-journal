import Foundation

/// Discovery / search member counts, carry into room detail until bootstrap supplies authority.
@MainActor
enum TradeRoomDiscoveryMemberCountCache {
    private static var counts: [RoomID: Int] = [:]

    static func record(_ suggestion: ExploreRoomSuggestion) {
        guard let count = suggestion.memberCount, count > 0 else { return }
        counts[suggestion.id] = count
    }

    static func record(roomID: RoomID, count: Int) {
        guard count > 0 else { return }
        counts[roomID] = count
    }

    static func knownCount(for roomID: RoomID) -> Int? {
        counts[roomID]
    }

    static func clear(roomID: RoomID) {
        counts.removeValue(forKey: roomID)
    }
}