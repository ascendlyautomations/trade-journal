import Foundation

#if DEBUG
/// DEBUG-only Trade Room discovery tracing — no private room content.
enum RoomDiscoveryProbe {
    nonisolated static func logMemberRooms(
        serverReturned: Int,
        decoded: Int,
        afterOwnedMerge: Int,
        droppedEmbed: Int
    ) {
        print(
            """
            [ROOM_DISCOVERY] memberRooms serverReturned=\(serverReturned) \
            decoded=\(decoded) afterOwnedMerge=\(afterOwnedMerge) \
            droppedEmbed=\(droppedEmbed)
            """
        )
    }

    nonisolated static func logBootstrapSection(
        section: String,
        serverReturned: Int,
        decoded: Int
    ) {
        print(
            """
            [ROOM_DISCOVERY] bootstrap section=\(section) \
            serverReturned=\(serverReturned) decoded=\(decoded)
            """
        )
    }

    nonisolated static func logClientFilter(
        section: String,
        before: Int,
        after: Int,
        reason: String
    ) {
        guard before != after else { return }
        print(
            """
            [ROOM_DISCOVERY] clientFilter section=\(section) \
            before=\(before) after=\(after) reason=\(reason)
            """
        )
    }

    nonisolated static func logDisplayed(
        memberCards: Int,
        discoveryRows: Int,
        mode: String
    ) {
        print(
            """
            [ROOM_DISCOVERY] displayed memberCards=\(memberCards) \
            discoveryRows=\(discoveryRows) mode=\(mode)
            """
        )
    }

    nonisolated static func logDropped(roomID: String?, reason: String) {
        print("[ROOM_DISCOVERY] dropped roomID=\(truncate(roomID)) reason=\(reason)")
    }

    nonisolated static func logMergedFromMembership(roomID: RoomID) {
        print("[ROOM_DISCOVERY] mergedFromMembership roomID=\(truncate(roomID.rawValue))")
    }

    nonisolated private static func truncate(_ raw: String?) -> String {
        guard let raw else { return "nil" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "nil" : trimmed }
        return String(trimmed.prefix(8)) + "…"
    }
}
#else
enum RoomDiscoveryProbe {
    nonisolated static func logMemberRooms(
        serverReturned: Int,
        decoded: Int,
        afterOwnedMerge: Int,
        droppedEmbed: Int
    ) {}
    nonisolated static func logBootstrapSection(section: String, serverReturned: Int, decoded: Int) {}
    nonisolated static func logClientFilter(section: String, before: Int, after: Int, reason: String) {}
    nonisolated static func logDisplayed(memberCards: Int, discoveryRows: Int, mode: String) {}
    nonisolated static func logDropped(roomID: String?, reason: String) {}
    nonisolated static func logMergedFromMembership(roomID: RoomID) {}
}
#endif
