import Foundation

/// All-scope Trade Rooms discovery ordering — authoritative RPC `member_count` only.
nonisolated enum TradeRoomDiscoveryMemberCountSort {
    /// Member count descending; stable tie-break: name (case-insensitive), then room id.
    static func sorted(_ rooms: [ExploreRoomSuggestion]) -> [ExploreRoomSuggestion] {
        rooms.sorted(by: isOrderedBefore)
    }

    static func isOrderedBefore(_ lhs: ExploreRoomSuggestion, _ rhs: ExploreRoomSuggestion) -> Bool {
        let leftCount = lhs.memberCount ?? Int.min
        let rightCount = rhs.memberCount ?? Int.min
        if leftCount != rightCount {
            return leftCount > rightCount
        }
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}
