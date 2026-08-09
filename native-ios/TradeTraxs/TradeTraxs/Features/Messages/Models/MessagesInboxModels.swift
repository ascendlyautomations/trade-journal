import Foundation

/// Presentation row for a direct-message conversation on Messages home.
struct DirectMessageInboxItem: Identifiable, Hashable, Sendable {
    var id: ConversationID { conversation.id }
    var conversation: Conversation
    var peer: Profile?
    var displayName: String
    var username: String?
    var preview: String
    var timestamp: Date?
    var unreadCount: Int
    var isMuted: Bool
    var isPinned: Bool
    var isTyping: Bool
    var isOnline: Bool
    /// Viewer has no unread — iMessage-style read affordance when preview exists.
    var showsReadReceipt: Bool
}

/// Presentation row for a Trade Room on Messages home / Trade Rooms home.
struct TradeRoomInboxItem: Identifiable, Hashable, Sendable {
    var id: RoomID { room.id }
    var room: TradeRoom
    var ownerName: String?
    var ownerIsVerified: Bool
    var preview: String
    var timestamp: Date?
    var unreadCount: Int
    var isMuted: Bool

    /// Public rooms show on profile; private rooms stay invite-only.
    var isPrivate: Bool { !room.showsOnProfile }
}

enum MessagesInboxSupport {
    static func isLocalDevelopmentProfile(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
    }

    static func message(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return UserFacingError.map(AppError.unknown(message: error.localizedDescription)).message
    }

    static func relativeTimestamp(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Now" }
        if interval < 3_600 {
            return "\(Int(interval / 60))m"
        }
        if interval < 86_400 {
            return "\(Int(interval / 3_600))h"
        }
        if interval < 86_400 * 7 {
            return "\(Int(interval / 86_400))d"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func peerID(in conversation: Conversation, viewerID: ProfileID?) -> ProfileID? {
        conversation.participantProfileIDs.first { $0 != viewerID }
            ?? conversation.participantProfileIDs.first
    }
}
