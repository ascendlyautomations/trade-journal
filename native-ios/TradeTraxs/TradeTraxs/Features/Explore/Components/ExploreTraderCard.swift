import SwiftUI

/// Compact suggested-trader card for the horizontal discovery rail.
struct ExploreTraderCard: View {
    let trader: ExploreTraderSuggestion
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    FollowListAvatarView(profile: trader.profile, imagePipeline: imagePipeline, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trader.profile.displayName)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text("@\(trader.profile.username)")
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(1)
                        if let identity = trader.identityLine {
                            Text(identity)
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                                .lineLimit(2)
                        }
                        if trader.followerCount > 0 {
                            Text("\(ProfileDisplay.compactCount(trader.followerCount)) followers")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onToggleFollow) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
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
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                isFollowing
                    ? "explore.trader.following.\(trader.id.rawValue)"
                    : "explore.trader.follow.\(trader.id.rawValue)"
            )
        }
        .padding(ExperienceSpacing.sm)
        .frame(width: 148, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(colors.surfacePrimary)
        )
        .accessibilityIdentifier("explore.trader.\(trader.id.rawValue)")
    }
}
