import SwiftUI

/// Vertical trader row, avatar, identity, and Follow/Following (Explore search + full list).
struct ExploreTraderListRow: View {
    let trader: ExploreTraderSuggestion
    let profile: Profile
    let viewerProfileID: ProfileID?
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let showsFollowControl: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    init(
        trader: ExploreTraderSuggestion,
        profile: Profile,
        viewerProfileID: ProfileID? = nil,
        imagePipeline: any ImagePipeline,
        isFollowing: Bool,
        showsFollowControl: Bool = true,
        onOpen: @escaping () -> Void,
        onToggleFollow: @escaping () -> Void
    ) {
        self.trader = trader
        self.profile = profile
        self.viewerProfileID = viewerProfileID
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
                            Text(traderDisplayName(profile))
                                .experienceStyle(.subheadline, color: colors.primaryText)
                                .fontWeight(.semibold)
                                .lineLimit(1)
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
            .buttonStyle(.experiencePlain)

            ExperienceProfileListFollowTrailing(
                profileID: profile.id,
                viewerProfileID: viewerProfileID,
                isFollowing: isFollowing,
                showsFollowControl: showsFollowControl,
                style: .exploreList,
                accessibilityPrefix: "explore.trader",
                onToggleFollow: onToggleFollow
            )
        }
        .accessibilityIdentifier("explore.trader.row.\(trader.id.rawValue)")
    }

    private func traderDisplayName(_ profile: Profile) -> String {
        let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? "Trader" : username
    }
}
