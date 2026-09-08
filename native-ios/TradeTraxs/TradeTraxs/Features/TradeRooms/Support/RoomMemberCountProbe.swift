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
    }
}
