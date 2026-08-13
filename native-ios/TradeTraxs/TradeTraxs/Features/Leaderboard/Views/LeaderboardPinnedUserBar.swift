import SwiftUI

/// Strava-style pinned “You” ranking strip — render-only.
struct LeaderboardPinnedUserBar: View {
    let row: LeaderboardRow
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                Divider().opacity(0.35)
                HStack(spacing: ExperienceSpacing.md) {
                    Text("You")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .textCase(.uppercase)
                    Text("#\(row.rank)")
                        .experienceStyle(.headline, color: colors.primaryText)
                        .monospacedDigit()
                    Spacer(minLength: ExperienceSpacing.sm)
                    Text(row.primaryMetricText)
                        .experienceStyle(.headline, color: metricColor)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                Divider().opacity(0.35)
            }
            .background(colors.fillSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboard.pinned.you")
    }

    private var metricColor: Color {
        if row.primaryMetricText.hasPrefix("+") { return colors.success }
        if row.primaryMetricText.hasPrefix("-") { return colors.error }
        return colors.primaryText
    }
}
