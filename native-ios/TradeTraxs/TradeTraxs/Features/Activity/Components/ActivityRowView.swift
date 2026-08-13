import SwiftUI

struct ActivityRowView: View {
    let row: ActivityRowModel
    var imagePipeline: (any ImagePipeline)?
    var onSelect: () -> Void
    var onSelectActor: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                avatar
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(row.primaryText)
                        .experienceStyle(.body, color: colors.primaryText)
                        .fontWeight(row.isUnread ? .semibold : .regular)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let secondary = row.secondaryText {
                        Text(secondary)
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: ExperienceSpacing.xs)
                VStack(alignment: .trailing, spacing: ExperienceSpacing.xxs) {
                    Text(row.relativeTimestamp)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    if row.isUnread {
                        Circle()
                            .fill(colors.accent)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .background(row.isUnread ? colors.secondaryBackground.opacity(0.55) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityIdentifier("activity.row.\(row.id.rawValue)")
    }

    @ViewBuilder
    private var avatar: some View {
        if row.showsSystemIcon {
            ZStack {
                Circle()
                    .fill(colors.secondaryBackground)
                ExperienceIcon(icon: .activity, size: .md, color: colors.secondaryText)
            }
            .frame(width: 40, height: 40)
        } else if let profile = row.actor, let imagePipeline {
            Group {
                if let onSelectActor {
                    Button(action: onSelectActor) {
                        FollowListAvatarView(
                            profile: profile,
                            imagePipeline: imagePipeline,
                            size: 40
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(profile.displayName)
                } else {
                    FollowListAvatarView(
                        profile: profile,
                        imagePipeline: imagePipeline,
                        size: 40
                    )
                }
            }
        } else {
            ExperienceAvatar(
                initials: ProfileDisplay.initials(
                    displayName: row.actor?.displayName ?? "?",
                    username: row.actor?.username ?? ""
                ),
                size: 40
            )
        }
    }
}
