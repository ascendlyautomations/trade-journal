import Foundation

/// Pending Trade Room deep-link focus (channel + highlighted message).
///
/// Seeded by push / universal-link routers before opening ``FeedRoute/room`` (or Messages / Profile room routes).
/// Consumed once by ``RoomConversationViewModel`` so features never parse URLs themselves.
@MainActor
final class RoomNavigationFocusStore {
    static let shared = RoomNavigationFocusStore()

    struct Focus: Equatable, Sendable {
        var roomID: RoomID
        var channelID: RoomChannelID?
        var messageID: MessageID?
    }

    private var pending: Focus?

    private init() {}

    func seed(_ focus: Focus) {
        pending = focus
    }

    func seed(roomID: RoomID, sectionID: String?, messageID: String?) {
        let channel = sectionID.flatMap { raw -> RoomChannelID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : RoomChannelID(trimmed)
        }
        let message = messageID.flatMap { raw -> MessageID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : MessageID(trimmed)
        }
        seed(Focus(roomID: roomID, channelID: channel, messageID: message))
    }

    func consume(for roomID: RoomID) -> Focus? {
        guard let pending, pending.roomID == roomID else { return nil }
        self.pending = nil
        return pending
    }

    func clear() {
        pending = nil
    }
}
