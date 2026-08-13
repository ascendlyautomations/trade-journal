import SwiftUI

/// Large Explore entry point into the native Leaderboards screen.
struct LeaderboardExploreCard: View {
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ExperienceSpacing.md) {
                ZStack {
                    Circle()
                        .fill(colors.accent.opacity(0.16))
                        .frame(width: 56, height: 56)
                    Image(systemName: AppIcon.leaderboard.systemName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(colors.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Leaderboards")
                        .experienceStyle(.title3, color: colors.primaryText)
                        .fontWeight(.bold)
                    Text("See how you stack up against traders you follow and the community.")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ExperienceSpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        colors.fillPrimary,
                        colors.accent.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .stroke(colors.accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("explore.leaderboards.card")
        .accessibilityLabel("Leaderboards")
        .accessibilityHint("Opens the Leaderboards screen")
    }
}
