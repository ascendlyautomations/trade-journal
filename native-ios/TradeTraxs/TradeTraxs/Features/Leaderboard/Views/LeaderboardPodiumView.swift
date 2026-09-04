import SwiftUI

/// Premium top-three podium — render-only, subtle entrance animation owned by the screen.
struct LeaderboardPodiumView: View {
    let podium: [LeaderboardRow]
    let profileFor: (ProfileID) -> Profile
    let imagePipeline: any ImagePipeline
    let animateEntrance: Bool
    let onOpen: (LeaderboardRow) -> Void
    let onEntranceFinished: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let podiumHeight: CGFloat = 184

    var body: some View {
        GeometryReader { geometry in
            let spacing = ExperienceSpacing.sm
            let horizontalInset = ExperienceSpacing.md * 2
            let columnGapTotal = spacing * 2
            let availableWidth = max(geometry.size.width - horizontalInset - columnGapTotal, 0)
            let sideWidth = availableWidth * 0.29
            let centerWidth = availableWidth * 0.42

            HStack(alignment: .bottom, spacing: spacing) {
                podiumSlot(rank: 2, width: sideWidth)
                podiumSlot(rank: 1, width: centerWidth, emphasized: true)
                podiumSlot(rank: 3, width: sideWidth)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .frame(height: podiumHeight)
        .padding(.vertical, ExperienceSpacing.md)
        .opacity(appeared ? 1 : (animateEntrance && !reduceMotion ? 0.01 : 1))
        .offset(y: appeared || reduceMotion || !animateEntrance ? 0 : 16)
        .onAppear {
            guard animateEntrance else {
                appeared = true
                return
            }
            ExperienceMotion.withAnimation(MotionSpring.gentle.animation, reduceMotion: reduceMotion) {
                appeared = true
            }
            onEntranceFinished()
        }
        .accessibilityIdentifier("leaderboard.podium")
    }

    @ViewBuilder
    private func podiumSlot(rank: Int, width: CGFloat, emphasized: Bool = false) -> some View {
        if let row = podium.first(where: { $0.rank == rank }) {
            Button {
                onOpen(row)
            } label: {
                card(for: row, emphasized: emphasized)
            }
            .buttonStyle(.plain)
            .frame(width: max(width, 0))
            .accessibilityIdentifier("leaderboard.podium.\(rank)")
        } else {
            Color.clear
                .frame(width: max(width, 0), height: emphasized ? 168 : 132)
        }
    }

    @ViewBuilder
    private func card(for row: LeaderboardRow, emphasized: Bool) -> some View {
        let profile = profileFor(row.profileID)
        VStack(spacing: ExperienceSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                FollowListAvatarView(
                    profile: profile,
                    imagePipeline: imagePipeline,
                    size: emphasized ? 68 : 52
                )
                Text(rankBadge(row.rank))
                    .font(.system(size: emphasized ? 13 : 11, weight: .bold))
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badgeColor(for: row.rank)))
                    .offset(x: 4, y: -4)
            }

            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text(profile.displayName)
                        .experienceStyle(emphasized ? .subheadline : .caption, color: colors.primaryText)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if row.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                if LeaderboardRowView.showsUsername(profile.username) {
                    Text("@\(profile.username)")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Text(row.primaryMetricText)
                    .experienceStyle(emphasized ? .subheadline : .caption, color: metricColor(row.primaryMetricText))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, ExperienceSpacing.xs)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity)
        .frame(minHeight: emphasized ? 168 : 132)
        .background(
            colors.fillPrimary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(emphasized ? colors.accent.opacity(0.45) : colors.border.opacity(0.35), lineWidth: emphasized ? 1.5 : 1)
        )
    }

    private func rankBadge(_ rank: Int) -> String {
        switch rank {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        default: return "\(rank)"
        }
    }

    private func badgeColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.84, green: 0.65, blue: 0.18)
        case 2: return Color(red: 0.62, green: 0.66, blue: 0.72)
        case 3: return Color(red: 0.72, green: 0.48, blue: 0.28)
        default: return colors.accent
        }
    }

    private func metricColor(_ text: String) -> Color {
        if text.hasPrefix("+") { return colors.success }
        if text.hasPrefix("-") { return colors.error }
        return colors.primaryText
    }
}
