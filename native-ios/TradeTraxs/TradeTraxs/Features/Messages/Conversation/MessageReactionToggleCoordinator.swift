import Foundation

/// Shared optimistic reaction toggle — Trade Rooms + DMs.
@MainActor
enum MessageReactionToggleCoordinator {
    static func toggle(
        messageID: MessageID,
        emoji: String,
        viewerID: ProfileID,
        reactions: [RoomMessageReaction],
        skipNetwork: Bool,
        patch: (_ messageID: MessageID, _ row: RoomMessageReaction, _ mode: MessageReactionSemantics.PatchMode) -> Void,
        insert: (_ row: RoomMessageReaction) async throws -> RoomMessageReaction,
        delete: (_ reactionID: String) async throws -> Void
    ) async {
        guard MessageReactionSemantics.supportedEmojis.contains(emoji) else { return }

        let existing = reactions.first(where: { $0.userID == viewerID && $0.reaction == emoji })

        if let existing {
            patch(messageID, existing, .delete)
            if skipNetwork {
                ExperienceHaptics.play(.selection)
                return
            }
            do {
                try await delete(existing.id)
                ExperienceHaptics.play(.selection)
            } catch {
                patch(messageID, existing, .insert)
                ExperienceHaptics.play(.error)
            }
            return
        }

        let optimistic = RoomMessageReaction(
            id: "optimistic-\(messageID.rawValue)-\(emoji)",
            messageID: RoomMessageID(messageID.rawValue),
            userID: viewerID,
            reaction: emoji,
            createdAt: nil
        )
        patch(messageID, optimistic, .insert)

        if skipNetwork {
            ExperienceHaptics.play(.selection)
            return
        }

        do {
            let saved = try await insert(optimistic)
            patch(messageID, optimistic, .delete)
            patch(messageID, saved, .insert)
            ExperienceHaptics.play(.selection)
        } catch {
            patch(messageID, optimistic, .delete)
            ExperienceHaptics.play(.error)
        }
    }
}
