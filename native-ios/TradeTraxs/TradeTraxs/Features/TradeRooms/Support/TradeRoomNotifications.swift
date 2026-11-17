import Foundation

extension Notification.Name {
    /// Posted when room metadata (name, description, image, privacy) changes. Object: `RoomID`.
    static let tradeRoomMetadataDidChange = Notification.Name("tradeRoomMetadataDidChange")
    /// Posted when channel list or channel metadata changes. Object: `RoomID`.
    static let tradeRoomChannelsDidChange = Notification.Name("tradeRoomChannelsDidChange")
    /// Posted when the viewer favorites or unfavorites a room. Object: `RoomID`.
    static let tradeRoomFavoriteDidChange = Notification.Name("tradeRoomFavoriteDidChange")
    /// Posted when the viewer joins or leaves a room. Object: `RoomID` when singular.
    static let tradeRoomMembershipDidChange = Notification.Name("tradeRoomMembershipDidChange")
}

enum TradeRoomNotificationKey {
    static let metadataRoom = "tradeRoomMetadataRoom"
    static let membershipJoined = "tradeRoomMembershipJoined"
    static let membershipRecord = "tradeRoomMembershipRecord"
}

extension Notification {
    var tradeRoomMetadataPayload: TradeRoom? {
        userInfo?[TradeRoomNotificationKey.metadataRoom] as? TradeRoom
    }
}
