import SwiftUI

/// Vertical trader row — avatar, identity, and Follow/Following (Explore search + full list).
struct ExploreTraderListRow: View {
    let trader: ExploreTraderSuggestion
    let profile: Profile
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let showsFollowControl: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    init(
        trader: ExploreTraderSuggestion,
        profile: Profile,
        imagePipeline: any ImagePipeline,
        isFollowing: Bool,
        showsFollowControl: Bool = true,
        onOpen: @escaping () -> Void,
        onToggleFollow: @escaping () -> Void
    ) {
        self.trader = trader
        self.profile = profile
        self.imagePipeline = imagePipeline
        self.isFollowing = isFollowing
        self.showsFollowControl = showsFollowControl
        self.onOpen = onOpen
        self.onToggleFollow = onToggleFollow
    }

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                    ExploreProfileAvatarView(profile: profile, imagePipeline: imagePipeline, diameter: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(profile.displayName)
                                .experienceStyle(.subheadline, color: colors.primaryText)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            if profile.isCreator {
                                TradeTraxsVerifiedBadge(size: .inline)
                            }
                        }
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsFollowControl {
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
                .accessibilityIdentifier(
                    isFollowing
                        ? "explore.trader.following.\(trader.id.rawValue)"
                        : "explore.trader.follow.\(trader.id.rawValue)"
                )
            }
        }
        .accessibilityIdentifier("explore.trader.row.\(trader.id.rawValue)")
    }
}
