import SwiftUI

/// Consolidated TraxsPro upsell for journal Trade Detail (AI, comparison, ticker history).
struct TradeDetailTraxProUpsellSection: View {
    let presentation: ProPremiumFeaturePresentation
    var trade: Trade?
    var profileID: ProfileID?
    var onRetryEntitlementVerification: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var canPresentPaywall: Bool {
        ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        )
    }

    var body: some View {
        Group {
            switch presentation {
            case .unrestricted:
                EmptyView()
            case .verifyingEntitlement:
                TraxProEntitlementVerificationInlineCard(
                    profileID: profileID,
                    onRetry: onRetryEntitlementVerification,
                    accessibilityIdentifier: "detail.trade.traxpro.entitlement.verification"
                )
            case .lockedPreview:
                lockedContent
            }
        }
        .accessibilityIdentifier("detail.trade.traxpro.upsell")
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            MonetizationPlanPresentation.ProMarketingHeader(
                title: MonetizationPlanCopy.tradeDetailPremiumHeadline,
                subtitle: MonetizationPlanCopy.tradeDetailPremiumSubtitle
            )

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                MonetizationPlanPresentation.ProMarketingFeatureList(
                    highlights: MonetizationPlanCopy.tradeDetailPremiumHighlights,
                    compact: true,
                    showsDividers: true
                )
            }

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(MonetizationPlanCopy.tradeDetailPremiumPreviewTitle)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Text(MonetizationPlanCopy.tradeDetailPremiumPreviewMessage)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                TradeDetailSampleComparisonCard()
                TradeDetailSampleTickerHistoryCard(ticker: trade?.symbol.ticker)
            }

            MonetizationPlanPresentation.TraxsProFeatureGateButtonStack(
                feature: .aiAnalyst,
                previewEntryPoint: .featurePreviewCard,
                previewAccessibilityIdentifier: "detail.trade.traxpro.preview",
                unlockAccessibilityIdentifier: "detail.trade.traxpro.upgrade"
            )

            if !canPresentPaywall, IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled {
                Text(
                    "TraxsPro upgrades aren't available in this build yet. "
                        + "Check back soon or contact support if you already subscribe."
                )
                .experienceStyle(.footnote, color: colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("detail.trade.traxpro.unavailable")
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .standard)
    }
}

// MARK: - Sample previews

private struct TradeDetailSampleDataBadge: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(MonetizationPlanCopy.tradeDetailSampleDataBadge.uppercased())
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(colors.tertiaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colors.fillSecondary, in: Capsule())
            .accessibilityLabel(MonetizationPlanCopy.tradeDetailSampleDataBadge)
    }
}

struct TradeDetailSampleComparisonCard: View {
    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.xs) {
                Text("Compared to Your Trades")
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                TradeDetailSampleDataBadge()
            }

            TradeDetailGroupedSurface {
                VStack(spacing: ExperienceSpacing.xs) {
                    sampleComparisonHeaderRow
                    sampleComparisonRow(
                        label: "P&L",
                        thisValue: "+$420",
                        avgValue: "+$185",
                        thisTone: colors.profit
                    )
                    sampleComparisonRow(
                        label: "Target R:R",
                        thisValue: "2.4R",
                        avgValue: "1.8R"
                    )
                    sampleComparisonRow(
                        label: "Hold",
                        thisValue: "42m",
                        avgValue: "1h 05m"
                    )
                    Text("↑ R:R was above your recent average on winners.")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier("detail.trade.traxpro.sample.comparison")
    }

    private var sampleComparisonHeaderRow: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("THIS")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .frame(width: 72, alignment: .trailing)
            Text("AVG")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func sampleComparisonRow(
        label: String,
        thisValue: String,
        avgValue: String,
        thisTone: Color? = nil
    ) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Text(label)
                .experienceStyle(.caption, color: colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(thisValue)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(thisTone ?? colors.primaryText)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(avgValue)
                .font(.system(.subheadline, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(colors.secondaryText)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct TradeDetailSampleTickerHistoryCard: View {
    var ticker: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var resolvedTicker: String {
        let trimmed = ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "NQ" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.xs) {
                Text("Your \(resolvedTicker) History")
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                TradeDetailSampleDataBadge()
            }

            TradeDetailGroupedSurface {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text("12 Previous Trades · 58% Win · 1.4 PF · +$3,240")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text("Avg Trade +$270")
                        .font(.system(.caption, design: .rounded).weight(.medium).monospacedDigit())
                        .foregroundStyle(theme.metricColor(for: 270))

                    Text(
                        "This trade’s result was stronger than your typical \(resolvedTicker) session over the last 30 days."
                    )
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("detail.trade.traxpro.sample.tickerHistory")
    }
}