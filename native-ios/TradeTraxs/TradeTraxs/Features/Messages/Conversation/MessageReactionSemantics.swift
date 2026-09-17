import Foundation

/// Shared message reaction semantics — web `lib/roomMessageReactions.ts` parity.
nonisolated enum MessageReactionSemantics {
    static let supportedEmojis: [String] = ["👍", "🔥", "😂", "‼️"]
    /// Double-tap "like" maps to the primary supported emoji (schema constraint).
    static let doubleTapLikeEmoji: String = "👍"

    static func aggregate(
        _ reactions: [RoomMessageReaction],
        viewerID: ProfileID?
    ) -> [RoomMessageReactionSummary] {
        var counts: [String: Int] = [:]
        var viewerSet: Set<String> = []

        for row in reactions {
            guard supportedEmojis.contains(row.reaction) else { continue }
            counts[row.reaction, default: 0] += 1
            if let viewerID, row.userID == viewerID {
                viewerSet.insert(row.reaction)
            }
        }

        return supportedEmojis.compactMap { emoji in
            let count = counts[emoji, default: 0]
            guard count > 0 else { return nil }
            return RoomMessageReactionSummary(
                emoji: emoji,
                count: count,
                reactedByViewer: viewerSet.contains(emoji)
            )
        }
    }

    static func patch(
        _ reactions: [RoomMessageReaction],
        next: RoomMessageReaction,
        mode: PatchMode
    ) -> [RoomMessageReaction] {
        switch mode {
        case .insert:
            let updated = reactions.filter { $0.userID != next.userID }
            if updated.contains(where: { $0.id == next.id }) {
                return updated
            }
            return updated + [next]
        case .delete:
            return reactions.filter { $0.id != next.id }
        }
    }

    enum PatchMode: Sendable {
        case insert
        case delete
    }
}
