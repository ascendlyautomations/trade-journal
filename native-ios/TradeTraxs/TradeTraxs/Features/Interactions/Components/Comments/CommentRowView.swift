import SwiftUI

struct CommentRowView: View {
    let comment: InteractionComment
    let isOwn: Bool
    var onDelete: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            ExperienceAvatar(
                initials: Self.initials(for: comment),
                size: 32
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: ExperienceSpacing.xs) {
                    Text(comment.authorUsername.map { "@\($0)" } ?? "Trader")
                        .experienceStyle(.footnote, color: colors.primaryText)
                    Text(TradeDisplay.dateText(comment.createdAt))
                        .experienceStyle(.caption, color: colors.tertiaryText)
                    Spacer(minLength: 0)
                    if isOwn, let onDelete {
                        Button("Delete", role: .destructive, action: onDelete)
                            .font(.caption)
                    }
                }
                Text(comment.body)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityIdentifier("interaction.comment.row.\(comment.id.rawValue)")
    }

    private static func initials(for comment: InteractionComment) -> String {
        ProfileDisplay.initials(
            displayName: comment.authorUsername ?? "",
            username: comment.authorUsername ?? "tr"
        )
    }
}
