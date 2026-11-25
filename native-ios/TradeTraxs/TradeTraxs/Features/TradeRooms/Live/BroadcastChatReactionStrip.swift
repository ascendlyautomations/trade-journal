import SwiftUI

/// Livestream chat list spacing (viewer + OBS studio panes).
enum BroadcastChatRowLayout {
    /// Gap between consecutive chat rows in the scroll list.
    static let listRowSpacing: CGFloat = 6
    /// Gap between attachments / text inside a row.
    static let bodyBlockSpacing: CGFloat = 4
    /// Gap between message body and reaction badges.
    static let reactionTopGap: CGFloat = 5
    static let rowVerticalPadding: CGFloat = 2
}

/// Compact livestream chat reaction badges (smaller than DM / room message pills).
struct BroadcastChatReactionStrip: View {
    let messageID: String
    let reactions: [BroadcastChatReactionItem]
    var viewerUserID: String?
    var isEnabled: Bool
    var onToggle: (String) -> Void

    @Environment(\.themeColors) private var colors

    private var summaries: [RoomMessageReactionSummary] {
        let mapped = reactions.map { row in
            RoomMessageReaction(
                id: row.id,
                messageID: RoomMessageID(row.messageId),
                userID: ProfileID(row.userId),
                reaction: row.emoji,
                createdAt: nil
            )
        }
        let viewer = viewerUserID.map { ProfileID($0) }
        return MessageReactionSemantics.aggregate(mapped, viewerID: viewer)
    }

    var body: some View {
        let rows = summaries
        if rows.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                ForEach(rows, id: \.emoji) { summary in
                    Button {
                        onToggle(summary.emoji)
                    } label: {
                        HStack(spacing: summary.count > 1 ? 1 : 0) {
                            Text(summary.emoji)
                                .font(.system(size: 10))
                            if summary.count > 1 {
                                Text("\(summary.count)")
                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        summary.reactedByViewer
                                            ? colors.accent
                                            : colors.tertiaryText
                                    )
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    summary.reactedByViewer
                                        ? colors.accent.opacity(0.18)
                                        : colors.fillSecondary.opacity(0.55)
                                )
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .disabled(!isEnabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("tradeRooms.broadcast.chat.reactions.\(messageID)")
        }
    }
}