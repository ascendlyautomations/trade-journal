import Foundation

enum ConversationThreadSupport {
    static func isLocalDevelopment(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
    }

    static func isLocalConversation(_ id: ConversationID) -> Bool {
        id.rawValue.hasPrefix("dev-") || id.rawValue.hasPrefix("dev.")
    }

    static func daySeparator(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func message(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        return UserFacingError.map(AppError.unknown(message: error.localizedDescription)).message
    }
}

enum ConversationTimelineItem: Identifiable, Hashable {
    case daySeparator(id: String, title: String)
    case message(ConversationBubbleItem)

    var id: String {
        switch self {
        case .daySeparator(let id, _): return "day-\(id)"
        case .message(let item): return item.id.rawValue
        }
    }
}

struct ConversationBubbleItem: Identifiable, Hashable {
    var id: MessageID
    var message: Message
    var isOutgoing: Bool
    var showsAvatar: Bool
    var showsTimestamp: Bool
    var sendState: SendState
    /// Per-bubble author for multi-sender threads (Trade Rooms). DMs leave this nil.
    var authorProfile: Profile? = nil
    /// Optional display name above incoming bubbles in rooms.
    var showsAuthorName: Bool = false

    enum SendState: Hashable {
        case sent
        case sending
        case failed
    }

    var imageReference: MediaReference? {
        message.attachments.first?.media
    }

    var text: String? {
        let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.isEmpty ? nil : body
    }
}
