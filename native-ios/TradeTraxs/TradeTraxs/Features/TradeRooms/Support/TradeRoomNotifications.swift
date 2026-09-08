import Foundation

extension Notification.Name {
    /// Posted when room metadata (name, description, image, privacy) changes. Object: `RoomID`.
    static let tradeRoomMetadataDidChange = Notification.Name("tradeRoomMetadataDidChange")
    /// Posted when channel list or channel metadata changes. Object: `RoomID`.
    static let tradeRoomChannelsDidChange = Notification.Name("tradeRoomChannelsDidChange")
}
