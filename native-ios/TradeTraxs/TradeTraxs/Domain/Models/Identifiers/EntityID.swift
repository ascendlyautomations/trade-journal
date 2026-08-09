import Foundation

// MARK: - Typed opaque identifiers
// Canonical identity types for the Domain layer. Navigation and Features
// reuse these (same module) — never invent parallel ID types per layer.

nonisolated struct UserID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct ProfileID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct TradeID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct TradeImageID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct TradeNoteID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct TradingAccountID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct JournalID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct PostID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct CommentID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct ReactionID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct StoryID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct ReelID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct ConversationID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct MessageID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct RoomID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct RoomMessageID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Web `room_sections.id` — a Trade Room channel (subroom).
nonisolated struct RoomChannelID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct NotificationID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct AchievementID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct ReferralID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct CalendarEventID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct SubscriptionID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

nonisolated struct ReportID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}
