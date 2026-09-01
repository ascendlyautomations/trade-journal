import Foundation

/// Web `lib/roomMessageReactions.ts` — V1 Trade Room message reactions.
nonisolated enum RoomMessageReactionSemantics {
    static let supportedEmojis: [String] = ["👍", "🔥", "😂", "‼️"]

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
            if reactions.contains(where: {
                $0.id == next.id
                    || ($0.userID == next.userID && $0.reaction == next.reaction)
            }) {
                return reactions
            }
            return reactions + [next]
        case .delete:
            return reactions.filter { $0.id != next.id }
        }
    }

    enum PatchMode: Sendable {
        case insert
        case delete
    }
}
