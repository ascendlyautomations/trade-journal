import Foundation

/// Notifies open DM / Trade Room threads when internal share completes.
enum SharedContentOutboundDelivery {
    enum Destination: Sendable, Equatable {
        case dm(ConversationID)
        case room(RoomID, channelID: RoomChannelID?)
    }

    struct Payload: Sendable {
        var destination: Destination
        var message: Message
    }

    static let notification = Notification.Name("SharedContentOutboundDelivery")

    @MainActor
    static func post(_ payload: Payload) {
        NotificationCenter.default.post(name: notification, object: payload)
    }
}
