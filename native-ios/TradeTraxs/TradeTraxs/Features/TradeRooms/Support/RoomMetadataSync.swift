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
        ExploreSessionStore.shared.applyRoomMetadata(from: room)
        NotificationCenter.default.post(
            name: .tradeRoomMetadataDidChange,
            object: room.id,
            userInfo: [TradeRoomNotificationKey.metadataRoom: room]
        )
    }

    static func channelsDidChange(roomID: RoomID) {
        NotificationCenter.default.post(name: .tradeRoomChannelsDidChange, object: roomID)
    }
}
