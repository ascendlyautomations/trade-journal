import Foundation

/// Server-confirmed membership rows from join RPC — consumed by open conversation screens.
@MainActor
enum TradeRoomConfirmedMembershipCache {
    private static var byRoom: [RoomID: RoomMembership] = [:]

    static func store(_ membership: RoomMembership, for roomID: RoomID) {
        byRoom[roomID] = membership
    }

    static func take(for roomID: RoomID) -> RoomMembership? {
        byRoom.removeValue(forKey: roomID)
    }

    static func resetForTesting() {
        byRoom = [:]
    }
}