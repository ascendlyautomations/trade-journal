import SwiftUI

/// Locked TraxsPro rule families in Settings → Trading Rules (Free tier).
struct TradingRulesPremiumLockedSection: View {
    @Environment(\.themeColors) private var colors

    private var showsInteractivePreview: Bool {
        TraxsProPreviewCoordinator.shared.canPresentPreview
    }

    private var canPresentPaywall: Bool {
        ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            header

            ForEach(TradingRulesPlanTier.PremiumRuleCategory.allCases, id: \.self) { category in
                categoryBlock(category)
            }

            actionButtons
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .featured)
        .accessibilityIdentifier("settings.tradingRules.premium.locked")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.accent)
                Text("TraxsPro Rules")
                    .experienceStyle(.headline, color: colors.primaryText)
            }
            Text(MonetizationPlanCopy.tradingRulesPremiumSectionSubtitle)
                .experienceStyle(.caption, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func categoryBlock(_ category: TradingRulesPlanTier.PremiumRuleCategory) -> some View {
        let cards = TradingRulesPlanTier.premiumRuleCards(for: category)
        if !cards.isEmpty {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(category.rawValue.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
                .tracking(0.6)
                .padding(.top, ExperienceSpacing.xxs)

            VStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    TradingRulesPremiumRuleRow(card: card)
                    if index < cards.count - 1 {
                        ExperienceDivider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(colors.fillSecondary.opacity(0.18), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            if showsInteractivePreview {
                Button {
                    ExperienceHaptics.play(.selection)
                    TraxsProPreviewCoordinator.shared.presentTradingRulesPreview(entryPoint: .tradingRulesGate)
                } label: {
                    Text(MonetizationPlanCopy.previewTraxsProRulesButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityIdentifier("settings.tradingRules.preview")
            }

            if canPresentPaywall {
                Button {
                    ExperienceHaptics.play(.selection)
                    ProUpgradeCoordinator.shared.present(
                        reason: .feature(.premiumAnalytics),
                        previewFeature: .tradingRules
                    )
                } label: {
                    Text(MonetizationPlanCopy.exploreTraxsProButtonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("settings.tradingRules.exploreTraxsPro")
            }
        }
        .padding(.top, ExperienceSpacing.xxs)
    }
}

private struct TradingRulesPremiumRuleRow: View {
    let card: TradingRulesPlanTier.PremiumRuleCard

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: card.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 32, height: 32)
                .background(colors.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Text(card.detail)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.sm)
        .accessibilityIdentifier("settings.tradingRules.premium.\(card.ruleID.rawValue)")
    }
}