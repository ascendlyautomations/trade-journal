import SwiftUI

/// Achievement post caption, title, description, and compact context (no table).
struct AchievementDetailMetadataSection: View {
    let achievement: Achievement

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var contextCaption: String? {
        AchievementDetailPresentation.contextCaption(for: achievement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            titleBlock

            if let description = normalizedDescription {
                Text(description)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("detail.achievement.description")
            }

            if let contextCaption {
                Text(contextCaption)
                    .experienceStyle(.footnote, color: colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("detail.achievement.context")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.achievement.metadata")
    }

    private var normalizedDescription: String? {
        let trimmed = achievement.description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private var titleBlock: some View {
        if ProfilePayoutTotals.isPayout(achievement.kind),
           let payoutText = ProfilePayoutTotals.payoutDisplayText(for: achievement)
        {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(payoutText)
                    .font(ExperienceTypography.headline.monospacedDigit())
                    .foregroundStyle(payoutAmountColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("detail.achievement.payoutAmount")

                Text(achievement.title)
                    .font(ExperienceTypography.headline)
                    .foregroundStyle(colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.achievement.payoutHeadline")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                Text(achievement.title)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer(minLength: ExperienceSpacing.xs)

                if let accessory = AchievementDetailPresentation.titleTrailingAccessory(for: achievement) {
                    Text(accessory)
                        .font(
                            AchievementDetailPresentation.trailingAccessoryUsesMetricColor(for: achievement)
                                ? ExperienceTypography.metric
                                : ExperienceTypography.caption
                        )
                        .foregroundStyle(trailingAccessoryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("detail.achievement.titleAccessory")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.achievement.title")
        }
    }

    private var payoutAmountColor: Color {
        if let value = achievement.value {
            return theme.metricColor(
                for: NSDecimalNumber(decimal: value.amount).doubleValue
            )
        }
        return colors.primaryText
    }

    private var trailingAccessoryColor: Color {
        if AchievementDetailPresentation.trailingAccessoryUsesMetricColor(for: achievement),
           let value = achievement.value
        {
            return theme.metricColor(
                for: NSDecimalNumber(decimal: value.amount).doubleValue
            )
        }
        return colors.secondaryText
    }
}
