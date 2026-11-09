import SwiftUI

struct MessageReplyReferenceView: View {
    let presentation: MessageReplySupport.ParentPresentation
    var isOutgoing: Bool
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onTap) {
            Group {
                if presentation.isUnavailable {
                    Text("Original message unavailable")
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(secondaryTextColor)
                } else {
                    let clipped = MessageReplySupport.truncatePreview(presentation.preview)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.authorName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(1)
                        if !clipped.isEmpty {
                            Text(clipped)
                                .font(.system(size: 11))
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(borderAccent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier("message.reply.reference")
    }

    private var backgroundColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.12) : Color.black.opacity(0.12)
    }

    private var borderAccent: Color {
        isOutgoing ? colors.onAccent.opacity(0.45) : colors.accent.opacity(0.7)
    }

    private var primaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.95) : colors.primaryText.opacity(0.9)
    }

    private var secondaryTextColor: Color {
        isOutgoing ? colors.onAccent.opacity(0.75) : colors.secondaryText
    }
}
