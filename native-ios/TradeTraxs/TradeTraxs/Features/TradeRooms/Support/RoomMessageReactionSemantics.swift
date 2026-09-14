import Foundation

/// Trade Room alias — shared semantics live in ``MessageReactionSemantics``.
nonisolated enum RoomMessageReactionSemantics {
    static var supportedEmojis: [String] { MessageReactionSemantics.supportedEmojis }
    static var doubleTapLikeEmoji: String { MessageReactionSemantics.doubleTapLikeEmoji }
    typealias PatchMode = MessageReactionSemantics.PatchMode

    static func aggregate(
        _ reactions: [RoomMessageReaction],
        viewerID: ProfileID?
    ) -> [RoomMessageReactionSummary] {
        MessageReactionSemantics.aggregate(reactions, viewerID: viewerID)
    }

    static func patch(
        _ reactions: [RoomMessageReaction],
        next: RoomMessageReaction,
        mode: PatchMode
    ) -> [RoomMessageReaction] {
        MessageReactionSemantics.patch(reactions, next: next, mode: mode)
    }
}
