import SwiftUI

/// Shared benefit rows for Plan settings, paywall sheets, and dashboard upsell.
enum MonetizationPlanPresentation {
    /// Top-trailing control on ``ProUpgradeGateSheet`` — opens the contextual TraxsPro sample preview.
    struct ProUpgradePreviewProToolbarButton: View {
        let accessibilityIdentifier: String
        let action: () -> Void

        @Environment(\.themeColors) private var colors

        var body: some View {
            Button(action: action) {
                Text(MonetizationPlanCopy.previewProButtonTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    struct ProMarketingHeader: View {
        let title: String
        let subtitle: String

        @Environment(\.themeColors) private var colors

        var body: some View {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(colors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(title)
                        .experienceStyle(.headline, color: colors.primaryText)
                        .fontWeight(.bold)
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct ProMarketingFeatureList: View {
        var compact: Bool = true
        var showsDividers: Bool = false

        @Environment(\.themeColors) private var colors

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? ExperienceSpacing.xs : ExperienceSpacing.sm) {
                ForEach(Array(MonetizationPlanCopy.paywallHighlights.enumerated()), id: \.element.id) { index, highlight in
                    PaywallHighlightRow(highlight: highlight, compact: compact)
                    if showsDividers, index < MonetizationPlanCopy.paywallHighlights.count - 1 {
                        Divider()
                            .overlay(colors.separator.opacity(0.35))
                            .padding(.leading, 32)
                    }
                }
            }
        }
    }

    /// Dashboard-only premium chart overview (Free tier bottom upsell).
    struct DashboardPremiumAnalyticsOverviewList: View {
        var compact: Bool = true
        var showsDividers: Bool = true

        @Environment(\.themeColors) private var colors

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? ExperienceSpacing.xs : ExperienceSpacing.sm) {
                ForEach(
                    Array(MonetizationPlanCopy.dashboardPremiumAnalyticsHighlights.enumerated()),
                    id: \.element.id
                ) { index, highlight in
                    PaywallHighlightRow(highlight: highlight, compact: compact)
                    if showsDividers, index < MonetizationPlanCopy.dashboardPremiumAnalyticsHighlights.count - 1 {
                        Divider()
                            .overlay(colors.separator.opacity(0.35))
                            .padding(.leading, 32)
                    }
                }
            }
        }
    }
    struct BenefitRow: View {
        let text: String
        var detail: String = ""

        @Environment(\.themeColors) private var colors

        var body: some View {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.accent)
                    .frame(width: 14, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !detail.isEmpty {
                        Text(detail)
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    struct PaywallHighlightRow: View {
        let highlight: MonetizationPlanCopy.PaywallHighlight
        var compact: Bool = false

        @Environment(\.themeColors) private var colors

        private var iconBox: CGFloat { compact ? 24 : 28 }

        var body: some View {
            HStack(alignment: .top, spacing: compact ? ExperienceSpacing.xs : ExperienceSpacing.sm) {
                Image(systemName: highlight.systemImage)
                    .font(compact ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(colors.accent)
                    .frame(width: iconBox, height: iconBox)
                    .background(colors.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(highlight.title)
                        .experienceStyle(compact ? .footnote : .subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                    Text(highlight.detail)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(compact ? 2 : nil)
                }
            }
        }
    }

    struct DisclosureToggle<Content: View>: View {
        let title: String
        let isExpanded: Bool
        let accessibilityID: String
        let onToggle: () -> Void
        @ViewBuilder let content: () -> Content

        @Environment(\.themeColors) private var colors

        var body: some View {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Button {
                    withAnimation(ExperienceMotion.navigation) {
                        onToggle()
                    }
                } label: {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Text(title)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.medium)
                        Spacer(minLength: ExperienceSpacing.xs)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.tertiaryText)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier(accessibilityID)

                if isExpanded {
                    content()
                }
            }
        }
    }

    /// StoreKit offer-code redemption — shared across paywall sheets and Settings subscription UI.
    struct AppleOfferCodeRedemptionButton: View {
        enum Style {
            /// Full-width bordered control (``ProUpgradeGateSheet`` secondary actions).
            case paywall
            /// Accent list-row control (Settings / post-onboarding plan cards).
            case settingsList
        }

        var style: Style
        var title: String = MonetizationPlanCopy.redeemAppleOfferCodeButtonTitle
        var isDisabled: Bool = false
        var accessibilityIdentifier: String
        var paymentsPausedFootnote: String? = nil
        let action: () -> Void

        @Environment(\.themeColors) private var colors

        var body: some View {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Group {
                    switch style {
                    case .paywall:
                        Button(action: action) {
                            Label(title, systemImage: "giftcard")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    case .settingsList:
                        Button(action: action) {
                            SettingsPrimaryActionLabel(title: title, systemImage: "giftcard")
                        }
                        .buttonStyle(.experiencePlain)
                    }
                }
                .disabled(isDisabled)
                .accessibilityIdentifier(accessibilityIdentifier)

                if let paymentsPausedFootnote {
                    Text(paymentsPausedFootnote)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct SelectedSubscriptionPriceCard: View {
        let product: StoreKitTraxProProduct?

        @Environment(\.themeColors) private var colors

        var body: some View {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Selected Plan:")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .fontWeight(.medium)
                if let product {
                    Text(product.displayName)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("proUpgrade.selectedDuration")
                    Text(product.displayPrice)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(colors.primaryText)
                        .accessibilityIdentifier("proUpgrade.selectedPrice")
                } else {
                    Text("Loading App Store pricing…")
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ExperienceSpacing.md)
            .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        }
    }
}