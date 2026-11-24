import SwiftUI

/// Upsell for full Trading Rules analytics (Free basic overview).
struct TradingRulesPremiumAnalyticsLockedSection: View {
    @Environment(\.themeColors) private var colors

    private let locks: [(title: String, detail: String)] = [
        ("Compliance trends", "Weekly and monthly adherence over time."),
        ("Violation breakdowns", "Most broken rules, worst days, and recurring patterns."),
        ("Rule impact", "How followed vs broken rules relate to your P&L."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Included with TraxsPro")
                .experienceStyle(.headline, color: colors.primaryText)

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(locks, id: \.title) { item in
                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(colors.tertiaryText)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colors.primaryText)
                            Text(item.detail)
                                .experienceStyle(.caption2, color: colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            MonetizationPlanPresentation.TraxsProFeatureGateButtonStack(
                feature: .premiumAnalytics,
                previewFeature: .tradingRules,
                previewEntryPoint: .tradingRulesGate,
                previewAccessibilityIdentifier: "tradingRulesAnalytics.preview",
                unlockAccessibilityIdentifier: "tradingRulesAnalytics.exploreTraxsPro"
            )
        }
        .padding(ExperienceSpacing.md)
        .experienceTradingRulesCard(prominence: .standard)
    }
}