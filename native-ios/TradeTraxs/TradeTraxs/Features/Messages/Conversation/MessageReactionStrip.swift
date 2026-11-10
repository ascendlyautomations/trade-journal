import SwiftUI

/// Aggregated reaction chip for message bubbles (DMs + Trade Rooms).
struct MessageReactionSummary: Hashable, Sendable {
    var emoji: String
    var count: Int
    var reactedByViewer: Bool

    init(emoji: String, count: Int, reactedByViewer: Bool) {
        self.emoji = emoji
        self.count = count
        self.reactedByViewer = reactedByViewer
    }

    init(_ room: RoomMessageReactionSummary) {
        emoji = room.emoji
        count = room.count
        reactedByViewer = room.reactedByViewer
    }
}

struct MessageReactionConfiguration: Hashable {
    var summaries: [MessageReactionSummary]
    var supportedEmojis: [String]
    var isEnabled: Bool
    var onToggle: (String) -> Void

    var showsStrip: Bool {
        !summaries.isEmpty || isEnabled
    }

    static func == (lhs: MessageReactionConfiguration, rhs: MessageReactionConfiguration) -> Bool {
        lhs.summaries == rhs.summaries
            && lhs.supportedEmojis == rhs.supportedEmojis
            && lhs.isEnabled == rhs.isEnabled
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(summaries)
        hasher.combine(supportedEmojis)
        hasher.combine(isEnabled)
    }
}

/// Layout metrics for floating reaction pills (DM + Trade Room bubbles).
enum MessageReactionLayout {
    /// Space between bubble bottom and the reaction row (before overlap pull-up).
    static let pillVerticalOffset: CGFloat = 6
    /// Pulls the reaction row up so pills lightly overlap the bubble bottom edge.
    static let pillBubbleEdgeOverlap: CGFloat = 5
    /// Gap between adjacent reaction pills (each pill keeps its own capsule background).
    static let pillSpacing: CGFloat = 4
    /// Layout space under the bubble for the floating row + breathing room before the next message.
    static let reservedSpaceBelowBubble: CGFloat = 20
    static let chipHorizontalInset: CGFloat = 6

    private static let rowHorizontalPadding: CGFloat = ExperienceSpacing.md
    private static let oppositeGutterMin: CGFloat = 48
    private static let incomingAvatarColumn: CGFloat = 28
    private static let avatarToContentSpacing: CGFloat = ExperienceSpacing.xs

    /// Max width for a reaction row extending from the bubble corner toward the thread center.
    static func maxHorizontalReach(isOutgoing: Bool) -> CGFloat {
        let viewport = UIScreen.main.bounds.width
        let sidePad = rowHorizontalPadding * 2
        if isOutgoing {
            return max(120, viewport - sidePad - oppositeGutterMin)
        }
        return max(
            120,
            viewport - sidePad - incomingAvatarColumn - avatarToContentSpacing - oppositeGutterMin
        )
    }
}

/// Compact floating reaction pills — shared by DMs and Trade Rooms.
struct MessageReactionStrip: View {
    let summaries: [MessageReactionSummary]
    let isOutgoing: Bool
    let isEnabled: Bool
    let onToggle: (String) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: MessageReactionLayout.pillSpacing) {
            ForEach(summaries, id: \.emoji) { summary in
                reactionPill(summary)
                    .transition(
                        .scale(scale: 0.82, anchor: .center)
                            .combined(with: .opacity)
                    )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: summaries)
    }

    private func reactionPill(_ summary: MessageReactionSummary) -> some View {
        Button {
            onToggle(summary.emoji)
        } label: {
            reactionPillContent(summary)
        }
        .buttonStyle(.experiencePlain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(summary.emoji) \(summary.count)\(summary.reactedByViewer ? ", you reacted" : "")")
        .accessibilityIdentifier("message.reaction.\(summary.emoji)")
    }

    private func reactionPillContent(_ summary: MessageReactionSummary) -> some View {
        HStack(spacing: summary.count > 1 ? 3 : 0) {
            Text(summary.emoji)
                .font(.system(size: 13))
            if summary.count > 1 {
                Text("\(summary.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(countLabelColor(reactedByViewer: summary.reactedByViewer))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(pillBackground(reactedByViewer: summary.reactedByViewer))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    pillBorderColor(reactedByViewer: summary.reactedByViewer),
                    lineWidth: summary.reactedByViewer ? 1 : 0.5
                )
        }
        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
    }

    private func pillBackground(reactedByViewer: Bool) -> Color {
        if reactedByViewer {
            return colors.accent.opacity(isOutgoing ? 0.16 : 0.18)
        }
        return colors.elevatedSurface.opacity(0.96)
    }

    private func pillBorderColor(reactedByViewer: Bool) -> Color {
        if reactedByViewer {
            return colors.accent.opacity(0.45)
        }
        return isOutgoing
            ? colors.border.opacity(0.75)
            : colors.border.opacity(0.85)
    }

    private func countLabelColor(reactedByViewer: Bool) -> Color {
        reactedByViewer ? colors.accent : colors.secondaryText
    }
}

/// Reaction row anchored to the bubble's trailing (sent) or leading (received) edge.
struct MessageReactionBubbleAttachment: View {
    let configuration: MessageReactionConfiguration
    let isOutgoing: Bool
    var columnMaxWidth: CGFloat? = nil

    private var rowAlignment: Alignment {
        isOutgoing ? .trailing : .leading
    }

    var body: some View {
        MessageReactionStrip(
            summaries: configuration.summaries,
            isOutgoing: isOutgoing,
            isEnabled: configuration.isEnabled,
            onToggle: configuration.onToggle
        )
        .frame(
            maxWidth: columnMaxWidth ?? MessageReactionLayout.maxHorizontalReach(isOutgoing: isOutgoing),
            alignment: rowAlignment
        )
        .padding(.leading, isOutgoing ? 0 : MessageReactionLayout.chipHorizontalInset)
        .padding(.trailing, isOutgoing ? MessageReactionLayout.chipHorizontalInset : 0)
        .allowsHitTesting(configuration.isEnabled)
        .accessibilityIdentifier("message.reaction.attachment")
    }
}

