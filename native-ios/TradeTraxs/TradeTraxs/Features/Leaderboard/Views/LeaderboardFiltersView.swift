import SwiftUI

/// Audience / timeframe / category controls — render-only; mutations go through the screen VM.
struct LeaderboardFiltersView: View {
    let audience: LeaderboardAudience
    let timeframe: LeaderboardTimeframe
    let category: LeaderboardCategory
    let onAudience: (LeaderboardAudience) -> Void
    let onTimeframe: (LeaderboardTimeframe) -> Void
    let onCategory: (LeaderboardCategory) -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Picker("Audience", selection: audienceBinding) {
                ForEach(LeaderboardAudience.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("leaderboard.audience")

            HStack(spacing: 4) {
                ForEach(LeaderboardTimeframe.allCases, id: \.self) { option in
                    timeframeChip(option)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityIdentifier("leaderboard.timeframe")

            Menu {
                ForEach(LeaderboardCategory.allCases, id: \.self) { option in
                    Button {
                        onCategory(option)
                    } label: {
                        if option == category {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    Text(category.title)
                        .experienceStyle(.body, color: colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.secondaryText)
                }
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.sm)
                .background(
                    colors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                )
            }
            .accessibilityIdentifier("leaderboard.category")
            .accessibilityLabel("Category")
            .accessibilityValue(category.title)
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private var audienceBinding: Binding<LeaderboardAudience> {
        Binding(
            get: { audience },
            set: { onAudience($0) }
        )
    }

    private func timeframeChip(_ option: LeaderboardTimeframe) -> some View {
        let selected = option == timeframe
        return Button {
            onTimeframe(option)
        } label: {
            Text(option.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(selected ? colors.onAccent : colors.primaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(selected ? colors.accent : colors.fillSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboard.timeframe.\(option.rawValue)")
    }
}
