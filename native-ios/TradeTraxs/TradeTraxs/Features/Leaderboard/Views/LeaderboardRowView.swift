import SwiftUI

/// Single ranked trader row — render-only.
struct LeaderboardRowView: View {
    let row: LeaderboardRow
    let imagePipeline: any ImagePipeline
    let showsFollowButton: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ExperienceSpacing.sm) {
                Text("#\(row.rank)")
                    .experienceStyle(.headline, color: colors.secondaryText)
                    .frame(width: 36, alignment: .leading)
                    .monospacedDigit()

                FollowListAvatarView(profile: row.profile, imagePipeline: imagePipeline, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(row.profile.displayName)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if row.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(colors.accent)
                        }
                    }
                    Text("@\(row.profile.username)")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: ExperienceSpacing.xs)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        trendIcon
                        Text(row.primaryMetricText)
                            .experienceStyle(.subheadline, color: primaryMetricColor)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    Text(row.secondaryMetricText)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(1)
                }

                if showsFollowButton {
                    Button(action: onToggleFollow) {
                        Text(row.isFollowing ? "Following" : "Follow")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(row.isFollowing ? colors.primaryText : colors.onAccent)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(
                                Capsule().fill(row.isFollowing ? colors.fillSecondary : colors.accent)
                            )
                            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboard.row.\(row.profileID.rawValue)")
    }

    private var trendIcon: some View {
        Image(systemName: trendSymbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(trendColor)
    }

    private var trendSymbol: String {
        switch row.trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }

    private var trendColor: Color {
        switch row.trend {
        case .up: return colors.success
        case .down: return colors.error
        case .flat: return colors.tertiaryText
        }
    }

    private var primaryMetricColor: Color {
        if row.primaryMetricText.hasPrefix("+") { return colors.success }
        if row.primaryMetricText.hasPrefix("-") { return colors.error }
        return colors.primaryText
    }
}
