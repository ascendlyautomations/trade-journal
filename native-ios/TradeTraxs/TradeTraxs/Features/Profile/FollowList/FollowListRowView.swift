import SwiftUI

struct FollowListRowView: View {
    let profile: Profile
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let showsRemove: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void
    let onRemove: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.md) {
            Button(action: onOpen) {
                HStack(spacing: ExperienceSpacing.md) {
                    FollowListAvatarView(profile: profile, imagePipeline: imagePipeline)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: ExperienceSpacing.xxs) {
                            Text(profile.displayName)
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundStyle(colors.primaryText)
                                .lineLimit(1)
                            if profile.isCreator {
                                ExperienceTag(title: "Creator", tone: .info)
                            }
                        }
                        Text("@\(profile.username)")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(colors.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("followList.row.\(profile.id.rawValue)")

            followControl

            if showsRemove {
                Menu {
                    Button("Remove", role: .destructive, action: onRemove)
                } label: {
                    ExperienceIcon(icon: .more, size: .sm, color: colors.secondaryText)
                        .frame(
                            width: ExperienceAccessibility.minTouchTarget,
                            height: ExperienceAccessibility.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("followList.removeMenu.\(profile.id.rawValue)")
            }
        }
        .padding(.horizontal, ExperienceSpacing.lg)
        .padding(.vertical, ExperienceSpacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var followControl: some View {
        Button(action: onToggleFollow) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(.footnote, design: .default).weight(.semibold))
                .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .fill(isFollowing ? colors.fillSecondary : colors.accent)
                )
                .overlay {
                    if isFollowing {
                        RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                            .stroke(colors.border, lineWidth: ExperienceBorder.thin)
                    }
                }
                .frame(
                    minWidth: ExperienceAccessibility.minTouchTarget,
                    minHeight: ExperienceAccessibility.minTouchTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            isFollowing
                ? "followList.following.\(profile.id.rawValue)"
                : "followList.follow.\(profile.id.rawValue)"
        )
    }
}
