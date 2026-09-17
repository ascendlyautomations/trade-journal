import SwiftUI

/// Compact reaction + actions card for long-press on message bubbles.
struct MessageBubbleActionMenu: View {
    let supportedEmojis: [String]
    var selectedEmoji: String? = nil
    let onSelectEmoji: (String) -> Void
    var onCopy: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDelete: (() -> Void)?
    var deleteTitle: String = "Delete"
    var onReport: (() -> Void)?
    let onDismiss: () -> Void

    @Environment(\.themeColors) private var colors

    private let emojiSlot: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            if !supportedEmojis.isEmpty {
                HStack(spacing: 0) {
                    ForEach(supportedEmojis, id: \.self) { emoji in
                        Button {
                            ExperienceHaptics.play(.selection)
                            onSelectEmoji(emoji)
                            onDismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 15))
                                .frame(width: emojiSlot, height: emojiSlot)
                                .background(
                                    selectedEmoji == emoji
                                        ? colors.fillSecondary.opacity(0.55)
                                        : Color.clear,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("React with \(emoji)")
                        .accessibilityIdentifier("message.reaction.menu.\(emoji)")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(width: emojiRowWidth)
            }

            if showsActionRows {
                if !supportedEmojis.isEmpty {
                    Divider().opacity(0.35)
                }
                VStack(spacing: 0) {
                    if let onCopy {
                        actionRow(title: "Copy", systemImage: "doc.on.doc", role: nil, action: onCopy)
                    }
                    if let onRetry {
                        actionRow(title: "Retry", systemImage: "arrow.clockwise", role: nil, action: onRetry)
                    }
                    if let onDelete {
                        actionRow(title: deleteTitle, systemImage: "trash", role: .destructive, action: onDelete)
                    }
                    if let onReport {
                        actionRow(title: "Report", systemImage: "flag", role: nil, action: onReport)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(colors.separator.opacity(0.35), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("message.actionMenu")
    }

    private var emojiRowWidth: CGFloat {
        CGFloat(supportedEmojis.count) * emojiSlot + 8
    }

    private var showsActionRows: Bool {
        onCopy != nil || onRetry != nil || onDelete != nil || onReport != nil
    }

    private func actionRow(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            ExperienceHaptics.play(role == .destructive ? .warning : .selection)
            action()
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(role == .destructive ? Color.red : colors.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: emojiRowWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
