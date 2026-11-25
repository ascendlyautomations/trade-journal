import Foundation

/// Shared optimistic reaction toggle, Trade Rooms + DMs.
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
    guard let normalized = MessageReactionValidation.normalize(emoji) else { return }

    let viewerRows = reactions.filter { $0.userID == viewerID }
    if let existing = viewerRows.first(where: {
      MessageReactionValidation.normalize($0.reaction) == normalized
    }) {
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

    for row in viewerRows {
      patch(messageID, row, .delete)
    }

    let optimistic = RoomMessageReaction(
      id: "optimistic-\(messageID.rawValue)-\(normalized)",
      messageID: RoomMessageID(messageID.rawValue),
      userID: viewerID,
      reaction: normalized,
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
      for row in viewerRows {
        patch(messageID, row, .insert)
      }
      ExperienceHaptics.play(.error)
    }
  }
}