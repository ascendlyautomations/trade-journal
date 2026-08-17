import SwiftUI
import UIKit

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
                }
                Text(comment.body)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = comment.body
                ExperienceHaptics.play(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if isOwn, let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier("interaction.comment.row.\(comment.id.rawValue)")
    }

    private static func initials(for comment: InteractionComment) -> String {
        ProfileDisplay.initials(
            displayName: comment.authorUsername ?? "",
            username: comment.authorUsername ?? "tr"
        )
    }
}
