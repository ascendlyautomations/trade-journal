import Foundation

@MainActor
enum RoomMetadataSync {
    static func apply(
        _ room: TradeRoom,
        inboxStore: MessagesInboxStore,
        detailCache: DetailPresentationCache,
        viewerID: ProfileID?
    ) {
        inboxStore.applyRoomMetadata(room)
        if let viewerID, room.ownerProfileID == viewerID {
            detailCache.seedOwnedTradeRoom(room, for: viewerID)
        }
        NotificationCenter.default.post(name: .tradeRoomMetadataDidChange, object: room.id)
    }

    static func channelsDidChange(roomID: RoomID) {
        NotificationCenter.default.post(name: .tradeRoomChannelsDidChange, object: roomID)
    }
}
