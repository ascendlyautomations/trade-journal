import SwiftUI

struct MessageReplyComposerStrip: View {
    let authorName: String
    let preview: String
    let onCancel: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        let clipped = MessageReplySupport.truncatePreview(preview)
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(colors.accent)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(authorName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .lineLimit(1)
                if !clipped.isEmpty {
                    Text("“\(clipped)”")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(colors.fillSecondary.opacity(0.45), in: Circle())
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.fillSecondary.opacity(0.35))
        .accessibilityIdentifier("message.reply.composerStrip")
    }
}
