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
        /// Pre-hydrated shared entities so open threads render cards on the first frame.
        var hydrationSnapshot: SharedContentHydrator.Snapshot?
    }

    static let notification = Notification.Name("SharedContentOutboundDelivery")

    @MainActor
    static func post(_ payload: Payload) {
        NotificationCenter.default.post(name: notification, object: payload)
    }
}
