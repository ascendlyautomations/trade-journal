import SwiftUI
import UIKit

/// Compact suggested-trader card for the horizontal discovery rail.
struct ExploreTraderCard: View {
    let trader: ExploreTraderSuggestion
    let profile: Profile
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    FollowListAvatarView(profile: profile, imagePipeline: imagePipeline, size: 52)
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
                    .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                    .contentShape(Rectangle())
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
        .contextMenu {
            Button(action: onOpen) {
                Label("View Profile", systemImage: "person.crop.circle")
            }
            Button {
                UIPasteboard.general.string = "@\(trader.profile.username)"
                ExperienceHaptics.play(.success)
            } label: {
                Label("Copy Username", systemImage: "doc.on.doc")
            }
            Button(action: onToggleFollow) {
                Label(
                    isFollowing ? "Unfollow" : "Follow",
                    systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus"
                )
            }
        } preview: {
            ExploreTraderCard(
                trader: trader,
                profile: profile,
                imagePipeline: imagePipeline,
                isFollowing: isFollowing,
                onOpen: {},
                onToggleFollow: {}
            )
        }
        .accessibilityIdentifier("explore.trader.\(trader.id.rawValue)")
    }
}
