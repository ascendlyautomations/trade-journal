import Foundation

/// Aggregate roots and the concepts they exclusively own.
///
/// Features must not mutate another aggregate's entities except through
/// that aggregate's repository / use cases.
nonisolated enum AggregateRoot: String, Sendable, CaseIterable {
    case trade
    case feed
    case messages
    case rooms
    case profile
    case home
}

nonisolated enum AggregateOwnership {
    /// Concepts owned by the Trade aggregate.
    static let tradeOwns: [String] = [
        "Trade",
        "TradeImage",
        "TradeNote",
        "TradeExecution",
        "TradeAnalysis",
        "TradeStatistics",
        "TradingAccount",
        "Journal",
        "JournalDay",
    ]

    /// Concepts owned by the Feed aggregate.
    static let feedOwns: [String] = [
        "FeedItem",
        "Post",
        "Comment",
        "Reaction",
        "Story",
        "Reel",
    ]

    /// Concepts owned by the Messages aggregate.
    static let messagesOwns: [String] = [
        "Conversation",
        "Message",
        "MessageAttachment",
        "ReadState",
    ]

    /// Concepts owned by the Rooms aggregate.
    static let roomsOwns: [String] = [
        "TradeRoom",
        "RoomMessage",
        "RoomMembership",
        "RoomModeration",
    ]

    /// Concepts owned by the Profile aggregate.
    static let profileOwns: [String] = [
        "User",
        "Profile",
        "FollowRelationship",
        "Creator",
        "ProfileStats",
        "Achievement",
        "Referral",
        "Subscription",
        "BillingStatus",
    ]

    /// Concepts owned by the Home aggregate.
    static let homeOwns: [String] = [
        "PerformanceSummary",
        "HomeWidget",
        "Insight",
        "HomeDashboard",
        "CalendarEvent",
    ]

    static func owner(of concept: String) -> AggregateRoot? {
        let map: [(AggregateRoot, [String])] = [
            (.trade, tradeOwns),
            (.feed, feedOwns),
            (.messages, messagesOwns),
            (.rooms, roomsOwns),
            (.profile, profileOwns),
            (.home, homeOwns),
        ]
        for (root, concepts) in map where concepts.contains(concept) {
            return root
        }
        return nil
    }
}
