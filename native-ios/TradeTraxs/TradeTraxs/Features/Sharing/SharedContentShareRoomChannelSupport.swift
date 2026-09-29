import Foundation

/// Posting rules for internal share → Trade Room — mirrors ``RoomConversationViewModel/canPostInSelectedChannel``.
enum SharedContentShareRoomChannelSupport {
    static func isRoomOwner(room: TradeRoom, viewerID: ProfileID) -> Bool {
        room.ownerProfileID == viewerID
    }

    static func canPost(in channel: RoomChannel, room: TradeRoom, viewerID: ProfileID) -> Bool {
        if isRoomOwner(room: room, viewerID: viewerID) { return true }
        return channel.allowMembersChat
    }

    static func postableChannels(
        from channels: [RoomChannel],
        room: TradeRoom,
        viewerID: ProfileID
    ) -> [RoomChannel] {
        channels.filter { canPost(in: $0, room: room, viewerID: viewerID) }
    }
}
