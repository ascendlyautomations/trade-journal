import SwiftUI

/// Single ranked trader row — render-only.
struct LeaderboardRowView: View {
    let row: LeaderboardRow
    let profile: Profile
    let imagePipeline: any ImagePipeline
    let showsFollowButton: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    private let rankWidth: CGFloat = 32
    private let avatarSize: CGFloat = 44
    private let metricWidth: CGFloat = 92
    private let followWidth: CGFloat = 76

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ExperienceSpacing.sm) {
                Text("#\(row.rank)")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .fontWeight(.semibold)
                    .frame(width: rankWidth, alignment: .leading)
                    .monospacedDigit()

                FollowListAvatarView(profile: profile, imagePipeline: imagePipeline, size: avatarSize)

                userInfoColumn
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                metricColumn
                    .frame(width: metricWidth, alignment: .trailing)

                if showsFollowButton {
                    followButton
                        .frame(width: followWidth, alignment: .trailing)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboard.row.\(row.profileID.rawValue)")
    }

    private var userInfoColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(profile.displayName)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if row.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.accent)
                }
            }
            if LeaderboardRowView.showsUsername(profile.username) {
                Text("@\(profile.username)")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var metricColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 3) {
                trendIcon
                Text(row.primaryMetricText)
                    .experienceStyle(.subheadline, color: primaryMetricColor)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if !row.secondaryMetricText.isEmpty {
                Text(row.secondaryMetricText)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var followButton: some View {
        Button(action: onToggleFollow) {
            Text(row.isFollowing ? "Following" : "Follow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.isFollowing ? colors.primaryText : colors.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, row.isFollowing ? 8 : 10)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(row.isFollowing ? colors.fillSecondary : colors.accent)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isFollowing ? "Following" : "Follow")
    }

    private var trendIcon: some View {
        Image(systemName: trendSymbol)
            .font(.system(size: 9, weight: .bold))
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

    static func showsUsername(_ username: String) -> Bool {
        ProfileIdentitySanitizer.leaderboardUsername(username) != nil
    }
}
