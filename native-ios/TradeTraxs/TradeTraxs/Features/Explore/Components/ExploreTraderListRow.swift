import SwiftUI

/// Vertical trader row — avatar, identity, and Follow/Following (Explore search + full list).
struct ExploreTraderListRow: View {
    let trader: ExploreTraderSuggestion
    let profile: Profile
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.md) {
            FollowListAvatarView(profile: profile, imagePipeline: imagePipeline, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("@\(profile.username)")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
                if let identity = trader.identityLine {
                    Text(identity)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: ExperienceSpacing.sm)
            Button(action: onToggleFollow) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        Capsule().fill(isFollowing ? colors.fillSecondary : colors.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("explore.trader.row.\(trader.id.rawValue)")
    }
}
