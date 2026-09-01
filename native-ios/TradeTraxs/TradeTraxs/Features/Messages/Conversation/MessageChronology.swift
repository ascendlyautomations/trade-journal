import Foundation

/// Canonical message chronology — single comparator for thread, cache, realtime, and inbox derivation.
nonisolated enum MessageChronology {
    /// Ascending thread order: oldest → newest.
    static func compareAscending(_ lhs: Message, _ rhs: Message) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    /// Descending order for newest-first queries.
    static func compareDescending(_ lhs: Message, _ rhs: Message) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.rawValue > rhs.id.rawValue
    }

    static func sortAscending(_ messages: [Message]) -> [Message] {
        messages.sorted(by: compareAscending)
    }

    static func sortDescending(_ messages: [Message]) -> [Message] {
        messages.sorted(by: compareDescending)
    }

    /// Newest canonical message in a collection.
    static func newest(in messages: [Message]) -> Message? {
        messages.max(by: compareAscending)
    }

    /// Oldest canonical message in a collection.
    static func oldest(in messages: [Message]) -> Message? {
        messages.min(by: compareAscending)
    }
}
