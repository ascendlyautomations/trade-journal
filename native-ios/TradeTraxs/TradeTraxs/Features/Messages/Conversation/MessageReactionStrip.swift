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
    /// Negative offset hangs pills slightly over the bubble bottom edge.
    static let pillOverlap: CGFloat = 7
    /// Clears the row beneath the bubble so pills never cover timestamps or the next message.
    static let reservedSpaceBelowBubble: CGFloat = 13
    static let chipHorizontalInset: CGFloat = 6
}

/// Compact floating reaction pills — shared by DMs and Trade Rooms.
struct MessageReactionStrip: View {
    let summaries: [MessageReactionSummary]
    let isOutgoing: Bool
    let isEnabled: Bool
    let onToggle: (String) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        MessageReactionFlowLayout(spacing: 3, rowSpacing: 3) {
            ForEach(summaries, id: \.emoji) { summary in
                reactionPill(summary)
                    .transition(
                        .scale(scale: 0.82, anchor: .center)
                            .combined(with: .opacity)
                    )
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: summaries)
    }

    private func reactionPill(_ summary: MessageReactionSummary) -> some View {
        Button {
            onToggle(summary.emoji)
        } label: {
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
            .background(pillBackground(reactedByViewer: summary.reactedByViewer), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        pillBorderColor(reactedByViewer: summary.reactedByViewer),
                        lineWidth: summary.reactedByViewer ? 1 : 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.experiencePlain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(summary.emoji) \(summary.count)\(summary.reactedByViewer ? ", you reacted" : "")")
        .accessibilityIdentifier("message.reaction.\(summary.emoji)")
    }

    private func pillBackground(reactedByViewer: Bool) -> Color {
        if reactedByViewer {
            return isOutgoing
                ? colors.onAccent.opacity(0.22)
                : colors.accent.opacity(0.18)
        }
        return isOutgoing
            ? colors.onAccent.opacity(0.12)
            : colors.surfacePrimary.opacity(0.96)
    }

    private func pillBorderColor(reactedByViewer: Bool) -> Color {
        if reactedByViewer {
            return isOutgoing ? colors.onAccent.opacity(0.55) : colors.accent.opacity(0.45)
        }
        return isOutgoing
            ? colors.onAccent.opacity(0.28)
            : colors.border.opacity(0.85)
    }

    private func countLabelColor(reactedByViewer: Bool) -> Color {
        if isOutgoing {
            return reactedByViewer
                ? colors.onAccent.opacity(0.95)
                : colors.onAccent.opacity(0.75)
        }
        return reactedByViewer ? colors.accent : colors.secondaryText
    }
}

/// Overlays grouped reaction pills on the message bubble corner (received → bottom-right, sent → bottom-left).
struct MessageReactionFloatingOverlayModifier: ViewModifier {
    let configuration: MessageReactionConfiguration?
    let isOutgoing: Bool

    private var summaries: [MessageReactionSummary] {
        configuration?.summaries ?? []
    }

    private var hasReactions: Bool {
        !summaries.isEmpty
    }

    private var cornerAlignment: Alignment {
        isOutgoing ? .bottomLeading : .bottomTrailing
    }

    private var stripAlignment: Alignment {
        isOutgoing ? .leading : .trailing
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: cornerAlignment) {
                if let configuration, hasReactions {
                    MessageReactionStrip(
                        summaries: configuration.summaries,
                        isOutgoing: isOutgoing,
                        isEnabled: configuration.isEnabled,
                        onToggle: configuration.onToggle
                    )
                    .padding(.horizontal, MessageReactionLayout.chipHorizontalInset)
                    .frame(maxWidth: .infinity, alignment: stripAlignment)
                    .offset(y: MessageReactionLayout.pillOverlap)
                    .allowsHitTesting(configuration.isEnabled)
                }
            }
            .padding(
                .bottom,
                hasReactions ? MessageReactionLayout.reservedSpaceBelowBubble : 0
            )
    }
}

extension View {
    func messageReactionFloatingOverlay(
        configuration: MessageReactionConfiguration?,
        isOutgoing: Bool
    ) -> some View {
        modifier(
            MessageReactionFloatingOverlayModifier(
                configuration: configuration,
                isOutgoing: isOutgoing
            )
        )
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
