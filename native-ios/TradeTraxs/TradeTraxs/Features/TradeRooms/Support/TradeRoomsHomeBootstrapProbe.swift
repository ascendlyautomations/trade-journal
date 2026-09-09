import Foundation

#if DEBUG
enum TradeRoomsHomeBootstrapProbe {
    nonisolated static func bootstrapReturned(_ bootstrap: TradeRoomsHomeBootstrap) {
        print(
            "[TradeRooms] bootstrapReturned rooms="
                + "your=\(bootstrap.yourRooms.count) "
                + "suggested=\(bootstrap.suggested.count) "
                + "popular=\(bootstrap.popular.count)"
        )
        for room in bootstrap.yourRooms {
            relationship(room)
        }
        print("[TradeRooms] yourRooms count=\(bootstrap.yourRooms.count)")
    }

    nonisolated static func initialCategory(_ mode: TradeRoomDiscoveryMode) {
        print("[TradeRooms] initialCategory=\(mode.rawValue)")
    }

    nonisolated private static func relationship(_ room: ExploreRoomSuggestion) {
        let member = room.isMember == true ? "true" : "false"
        let owner = room.isOwner == true ? "true" : "false"
        print("[TradeRooms] relationship roomID=\(room.id.rawValue) isMember=\(member) isOwner=\(owner)")
    }
}
#else
enum TradeRoomsHomeBootstrapProbe {
    static func bootstrapReturned(_ bootstrap: TradeRoomsHomeBootstrap) {}
    static func initialCategory(_ mode: TradeRoomDiscoveryMode) {}
}
#endif
