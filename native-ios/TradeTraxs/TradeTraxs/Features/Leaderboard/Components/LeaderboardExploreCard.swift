import SwiftUI

/// Compact Explore entry into Leaderboards — navigation row, not a hero card.
struct LeaderboardExploreCard: View {
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    private enum Metrics {
        static let iconDiameter: CGFloat = 44
        static let rowMinHeight: CGFloat = 72
        static let cornerRadius = ExperienceRadius.sm
    }

    private let subtitle = "Rankings across the community"

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ExperienceSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(colors.accentMuted)
                        .frame(width: Metrics.iconDiameter, height: Metrics.iconDiameter)
                    Image(systemName: AppIcon.leaderboard.systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboards")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm + 2)
            .frame(minHeight: Metrics.rowMinHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfacePrimary)
            .clipShape(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("explore.leaderboards.card")
        .accessibilityLabel("Leaderboards. \(subtitle)")
        .accessibilityHint("Opens the Leaderboards screen")
    }
}
