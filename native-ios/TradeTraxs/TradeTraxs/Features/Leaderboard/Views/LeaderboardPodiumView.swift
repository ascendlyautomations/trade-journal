import SwiftUI

/// Premium top-three podium — render-only, subtle entrance animation owned by the screen.
struct LeaderboardPodiumView: View {
    let podium: [LeaderboardRow]
    let imagePipeline: any ImagePipeline
    let animateEntrance: Bool
    let onOpen: (LeaderboardRow) -> Void
    let onEntranceFinished: () -> Void

    @Environment(\.themeColors) private var colors
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
            podiumSlot(rank: 2)
            podiumSlot(rank: 1)
            podiumSlot(rank: 3)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.md)
        .opacity(appeared ? 1 : 0.01)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            guard animateEntrance else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
            onEntranceFinished()
        }
        .accessibilityIdentifier("leaderboard.podium")
    }

    @ViewBuilder
    private func podiumSlot(rank: Int) -> some View {
        if let row = podium.first(where: { $0.rank == rank }) {
            Button {
                onOpen(row)
            } label: {
                card(for: row, emphasized: rank == 1)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("leaderboard.podium.\(rank)")
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: rank == 1 ? 168 : 132)
        }
    }

    private func card(for row: LeaderboardRow, emphasized: Bool) -> some View {
        VStack(spacing: ExperienceSpacing.sm) {
            ZStack(alignment: .topTrailing) {
                FollowListAvatarView(
                    profile: row.profile,
                    imagePipeline: imagePipeline,
                    size: emphasized ? 72 : 56
                )
                Text(rankBadge(row.rank))
                    .font(.system(size: emphasized ? 14 : 12, weight: .bold))
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeColor(for: row.rank)))
                    .offset(x: 6, y: -6)
            }

            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text(row.profile.displayName)
                        .experienceStyle(emphasized ? .headline : .subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if row.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
                Text("@\(row.profile.username)")
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(1)
                Text(row.primaryMetricText)
                    .experienceStyle(emphasized ? .body : .subheadline, color: metricColor(row.primaryMetricText))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .padding(ExperienceSpacing.sm)
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
        .scaleEffect(emphasized ? 1.04 : 1)
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
