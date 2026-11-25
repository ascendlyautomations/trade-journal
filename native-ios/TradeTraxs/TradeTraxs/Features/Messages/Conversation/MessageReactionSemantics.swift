import Foundation

/// Shared message reaction semantics, web `lib/roomMessageReactions.ts` parity.
nonisolated enum MessageReactionSemantics {
  static let quickPickEmojis: [String] = ["❤️", "👍", "🔥", "😂", "‼️"]
  /// Legacy name for action menus.
  static var supportedEmojis: [String] { quickPickEmojis }
  /// Double-tap toggles heart (default like).
  static let doubleTapLikeEmoji: String = "❤️"

  static func aggregate(
    _ reactions: [RoomMessageReaction],
    viewerID: ProfileID?
  ) -> [RoomMessageReactionSummary] {
    var counts: [String: Int] = [:]
    var viewerEmoji: String?

    for row in reactions {
      guard let emoji = MessageReactionValidation.normalize(row.reaction) else { continue }
      counts[emoji, default: 0] += 1
      if let viewerID, row.userID == viewerID {
        viewerEmoji = emoji
      }
    }

    return counts.keys.sorted { lhs, rhs in
      let lc = counts[lhs, default: 0]
      let rc = counts[rhs, default: 0]
      if lc != rc { return lc > rc }
      return lhs < rhs
    }
    .map { emoji in
      RoomMessageReactionSummary(
        emoji: emoji,
        count: counts[emoji, default: 0],
        reactedByViewer: viewerEmoji == emoji
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
      guard let emoji = MessageReactionValidation.normalize(next.reaction) else { return reactions }
      let withoutViewer = reactions.filter { $0.userID != next.userID }
      if withoutViewer.contains(where: { $0.id == next.id }) {
        return withoutViewer
      }
      return withoutViewer + [
        RoomMessageReaction(
          id: next.id,
          messageID: next.messageID,
          userID: next.userID,
          reaction: emoji,
          createdAt: next.createdAt
        )
      ]
    case .delete:
      return reactions.filter { $0.id != next.id }
    }
  }

  enum PatchMode: Sendable {
    case insert
    case delete
  }
}