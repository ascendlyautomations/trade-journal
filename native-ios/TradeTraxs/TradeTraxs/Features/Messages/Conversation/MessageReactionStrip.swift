import SwiftUI

/// Aggregated reaction chip for message bubbles (Trade Rooms today; DMs when backend adds support).
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

/// Compact inline reaction chips for the bottom of a message bubble.
struct MessageReactionStrip: View {
    let summaries: [MessageReactionSummary]
    let supportedEmojis: [String]
    let isOutgoing: Bool
    let isEnabled: Bool
    let onToggle: (String) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        MessageReactionFlowLayout(spacing: 4, rowSpacing: 4) {
            ForEach(summaries, id: \.emoji) { summary in
                reactionChip(summary)
            }
            reactMenu
        }
    }

    private var reactMenu: some View {
        Menu {
            ForEach(supportedEmojis, id: \.self) { emoji in
                Button {
                    onToggle(emoji)
                } label: {
                    Text(emoji)
                }
                .disabled(!isEnabled)
            }
        } label: {
            Image(systemName: "face.smiling")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryLabelColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(chipBackground(reactedByViewer: false), in: Capsule())
        }
        .disabled(!isEnabled)
        .accessibilityIdentifier("message.reaction.menu")
    }

    private func reactionChip(_ summary: MessageReactionSummary) -> some View {
        Button {
            onToggle(summary.emoji)
        } label: {
            HStack(spacing: 2) {
                Text(summary.emoji)
                    .font(.caption)
                Text("\(summary.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryLabelColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(chipBackground(reactedByViewer: summary.reactedByViewer), in: Capsule())
            .overlay(
                Capsule().stroke(
                    summary.reactedByViewer ? chipBorderColor : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(summary.emoji) \(summary.count)\(summary.reactedByViewer ? ", you reacted" : "")")
        .accessibilityIdentifier("message.reaction.\(summary.emoji)")
    }

    private func chipBackground(reactedByViewer: Bool) -> Color {
        if isOutgoing {
            return reactedByViewer
                ? colors.onAccent.opacity(0.28)
                : colors.onAccent.opacity(0.14)
        }
        return reactedByViewer
            ? colors.accent.opacity(0.22)
            : colors.fillSecondary.opacity(0.9)
    }

    private var chipBorderColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.45) : colors.accent.opacity(0.35)
    }

    private var secondaryLabelColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.88) : colors.secondaryText
    }
}

private struct MessageReactionFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        if maxWidth.isFinite, maxWidth > 0 {
            return laidOutSize(subviews: subviews, maxWidth: maxWidth)
        }
        return laidOutSize(subviews: subviews, maxWidth: .infinity)
    }

    private func laidOutSize(subviews: Subviews, maxWidth: CGFloat) -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        let wraps = maxWidth.isFinite

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if wraps, x > 0, x + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        maxRowWidth = max(maxRowWidth, x > 0 ? x - spacing : 0)
        let width = wraps ? maxRowWidth : x > 0 ? x - spacing : 0
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
