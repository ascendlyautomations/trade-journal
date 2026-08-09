import SwiftUI

struct ProfileAchievementCard: View {
    let achievement: Achievement
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var target: InteractionTarget { .achievement(achievement.id) }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                        TradeImageView(
                            reference: achievement.image,
                            imagePipeline: imagePipeline
                        )
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            HStack(spacing: ExperienceSpacing.xs) {
                                if achievement.isFeatured {
                                    ExperienceTag(title: "Featured", tone: .success)
                                }
                                ExperienceTag(title: achievement.tier.rawValue.capitalized, tone: .info)
                                Spacer(minLength: 0)
                            }

                            Text(achievement.title)
                                .experienceStyle(.headline, color: colors.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            if let description = achievement.description?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !description.isEmpty {
                                Text(description)
                                    .experienceStyle(.footnote, color: colors.secondaryText)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }

                            HStack(spacing: ExperienceSpacing.sm) {
                                Text(kindLabel)
                                    .experienceStyle(.caption, color: colors.tertiaryText)
                                if let firm = achievement.firm, !firm.isEmpty {
                                    Text(firm)
                                        .experienceStyle(.caption, color: colors.tertiaryText)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if let value = achievement.value {
                                    Text(TradeDisplay.pnlText(value))
                                        .experienceStyle(
                                            .metric,
                                            color: theme.metricColor(
                                                for: NSDecimalNumber(decimal: value.amount).doubleValue
                                            )
                                        )
                                } else if let valueText = achievement.valueText, !valueText.isEmpty {
                                    Text(valueText)
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                            }

                            Text(TradeDisplay.dateText(achievement.achievedAt))
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)

                EngagementBar(
                    target: target,
                    store: engagementStore,
                    onCommentTap: onOpen
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.achievements.card.\(achievement.id.rawValue)")
    }

    private var kindLabel: String {
        switch achievement.kind {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Passed Eval"
        case .milestone: return "Milestone"
        }
    }
}
