import Foundation

/// Authoritative active membership: `room_members` rows with `left_at IS NULL`.
enum RoomMemberCountAuthority {
    static func resolve(
        memberStats: RoomsBootstrapV1.MemberStatsWire?,
        activeMemberCount: Int?
    ) -> Int {
        if let stats = memberStats {
            return stats.active_members
        }
        return activeMemberCount ?? 0
    }
}

/// Reconciles list-derived counts with bootstrap/discovery when RLS hides `room_members`.
enum RoomMemberCountReconcile {
    /// Non-members often get `0` from `activeMemberCounts` — do not clobber a known positive count.
    static func choose(
        listedActiveCount: Int?,
        currentCount: Int?,
        viewerCanQueryMemberList: Bool
    ) -> Int? {
        if let listed = listedActiveCount, listed > 0 {
            return listed
        }
        if viewerCanQueryMemberList, let listed = listedActiveCount {
            return listed
        }
        if let current = currentCount, current > 0 {
            return current
        }
        return listedActiveCount ?? currentCount
    }

    static func adjustedAfterMembershipChange(currentCount: Int?, delta: Int) -> Int? {
        guard let current = currentCount else { return nil }
        return max(0, current + delta)
    }
}

#if DEBUG
enum RoomMemberCountProbe {
    enum Source: String {
        case cache
        case network
        case bootstrap
        case realtime
        case mutation
    }

    static func record(
        roomID: RoomID,
        displayedMemberCount: Int?,
        activeMembershipCount: Int?,
        loadedMemberListCount: Int?,
        source: Source
    ) {
        print(
            "[RoomMemberCount] roomId=\(roomID.rawValue) "
                + "displayedMemberCount=\(displayedMemberCount.map(String.init) ?? "nil") "
                + "activeMembershipCount=\(activeMembershipCount.map(String.init) ?? "nil") "
                + "loadedMemberListCount=\(loadedMemberListCount.map(String.init) ?? "nil") "
                + "source=\(source.rawValue)"
        )
    }
}
#else
enum RoomMemberCountProbe {
    enum Source: String {
        case cache
        case network
        case bootstrap
        case realtime
        case mutation
    }

    static func record(
        roomID: RoomID,
        displayedMemberCount: Int?,
        activeMembershipCount: Int?,
        loadedMemberListCount: Int?,
        source: Source
    ) {}
}
#endif

@MainActor
enum RoomMemberCountSync {
    static func apply(
        roomID: RoomID,
        count: Int,
        inboxStore: MessagesInboxStore,
        viewerID: ProfileID?
    ) {
        inboxStore.applyMemberCounts([roomID: count])
        if let viewerID {
            SessionMemberRoomsStore.shared.applyMemberCounts([roomID: count], for: viewerID)
        }
        TradeRoomDiscoveryMemberCountCache.record(roomID: roomID, count: count)
    }

    static func applyDelta(
        roomID: RoomID,
        delta: Int,
        inboxStore: MessagesInboxStore,
        viewerID: ProfileID?
    ) {
        inboxStore.applyMemberCountDelta(roomID: roomID, delta: delta)
        if let viewerID {
            SessionMemberRoomsStore.shared.applyMemberCountDelta(
                roomID: roomID,
                delta: delta,
                for: viewerID
            )
        }
        if let next = RoomMemberCountReconcile.adjustedAfterMembershipChange(
            currentCount: TradeRoomDiscoveryMemberCountCache.knownCount(for: roomID),
            delta: delta
        ) {
            TradeRoomDiscoveryMemberCountCache.record(roomID: roomID, count: next)
        }
    }
}
