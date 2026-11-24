import SwiftUI

/// Shared benefit rows for Plan settings, paywall sheets, and dashboard upsell.
enum MonetizationPlanPresentation {
    /// Top-trailing control on ``ProUpgradeGateSheet``, opens the contextual TraxsPro sample preview.
    struct ProUpgradePreviewProToolbarButton: View {
        let previewFeature: TraxsProPreviewFeature
        let accessibilityIdentifier: String
        let action: () -> Void

        @Environment(\.themeColors) private var colors

        var body: some View {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(MonetizationPlanCopy.paywallPreviewFeatureTitle(for: previewFeature))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(colors.accent)
                    Text(MonetizationPlanCopy.paywallPreviewProBadge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(colors.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(MonetizationPlanCopy.paywallPreviewFeatureTitle(for: previewFeature)) "
                    + MonetizationPlanCopy.paywallPreviewProBadge
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    /// Shared Free-tier actions under gated TraxsPro surfaces (Reports reference layout).
    struct TraxsProFeatureGateButtonStack: View {
        let feature: ProFeatureKind
        var previewFeature: TraxsProPreviewFeature? = nil
        var previewEntryPoint: TraxsProPreviewEntryPoint = .featurePreviewCard
        let previewAccessibilityIdentifier: String
        let unlockAccessibilityIdentifier: String

        @Environment(\.themeColors) private var colors

        private var resolvedPreviewFeature: TraxsProPreviewFeature? {
            previewFeature ?? TraxsProPreviewCatalog.previewFeature(for: feature)
        }

        private var showsPreviewButton: Bool {
            TraxsProPreviewCatalog.supportsInteractivePreview(for: feature)
                && TraxsProPreviewCoordinator.shared.canPresentPreview
                && resolvedPreviewFeature != nil
        }

        private var showsUnlockButton: Bool {
            ProMonetizationPolicy.canPresentProPaywall(
                demoModeActive: ExploreModeSupport.isActive,
                enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
                paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
            )
        }

        var body: some View {
            VStack(spacing: ExperienceSpacing.sm) {
                if showsPreviewButton, let resolvedPreviewFeature {
                    Button {
                        ExperienceHaptics.play(.selection)
                        TraxsProPreviewCoordinator.shared.presentPreview(
                            feature: resolvedPreviewFeature,
                            entryPoint: previewEntryPoint
                        )
                    } label: {
                        gateButtonTitle(MonetizationPlanCopy.previewWithSampleDataButtonTitle)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityIdentifier(previewAccessibilityIdentifier)
                }

                if showsUnlockButton {
                    Button {
                        ExperienceHaptics.play(.selection)
                        ProUpgradeCoordinator.shared.present(
                            reason: .feature(feature),
                            previewFeature: previewFeature
                        )
                    } label: {
                        gateButtonTitle(MonetizationPlanCopy.paywallUnlockTitle)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: ExperienceRadius.sm))
                    .controlSize(.regular)
                    .tint(colors.accent)
                    .accessibilityIdentifier(unlockAccessibilityIdentifier)
                }
            }
        }

        private func gateButtonTitle(_ title: String) -> some View {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
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

    /// Collapsible improvement outcomes on the upgrade paywall.
    struct ProMarketingOutcomeList: View {
        var compact: Bool = true

        @Environment(\.themeColors) private var colors

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? ExperienceSpacing.xs : ExperienceSpacing.sm) {
                ForEach(Array(MonetizationPlanCopy.paywallOutcomeHighlights.enumerated()), id: \.element.id) { index, highlight in
                    PaywallHighlightRow(highlight: highlight, compact: compact)
                    if index < MonetizationPlanCopy.paywallOutcomeHighlights.count - 1 {
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

    /// StoreKit offer-code redemption, shared across paywall sheets and Settings subscription UI.
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

    /// Settings → Plan expandable benefit summaries.
    struct PlanFeatureSummaryList: View {
        let highlights: [MonetizationPlanCopy.PaywallHighlight]

        @Environment(\.themeColors) private var colors

        var body: some View {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                    PaywallHighlightRow(highlight: highlight, compact: true)
                    if index < highlights.count - 1 {
                        Divider()
                            .overlay(colors.separator.opacity(0.35))
                            .padding(.leading, 32)
                    }
                }
            }
        }
    }

    /// One selectable duration inside the grouped Settings plan card.
    struct SubscriptionPlanOptionRow: View {
        let product: StoreKitTraxProProduct
        let isSelected: Bool
        let accessibilityIdentifier: String
        let action: () -> Void

        @Environment(\.themeColors) private var colors
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text(planTitle)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                        Text(product.displayPrice)
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                        Text(MonetizationPlanCopy.settingsPlanPeriodBlurb(for: product))
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let offer = product.introductoryOfferSummary {
                            Text(offer)
                                .experienceStyle(.caption2, color: colors.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: ExperienceSpacing.sm)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(isSelected ? colors.accent : colors.tertiaryText)
                }
                .padding(ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .fill(isSelected ? colors.accent.opacity(colorScheme == .light ? 0.1 : 0.16) : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? colors.accent.opacity(colorScheme == .light ? 0.55 : 0.45)
                                : colors.border.opacity(colorScheme == .light ? 0.28 : 0.22),
                            lineWidth: ExperienceBorder.hairline
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier(accessibilityIdentifier)
        }

        private var planTitle: String {
            let label = product.subscriptionPeriodLabel
            return label == "Subscription" ? product.displayName : label
        }
    }

    struct SettingsPlanPrimaryUpgradeButton: View {
        let title: String
        let isLoading: Bool
        let isDisabled: Bool
        let accessibilityIdentifier: String
        let action: () -> Void

        @Environment(\.themeColors) private var colors

        var body: some View {
            Button(action: action) {
                SettingsPlanActionLabel(title: title, isLoading: isLoading)
                    .foregroundStyle(colors.onAccent)
                    .background(
                        colors.accent,
                        in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    struct SettingsPlanSecondaryActionButton: View {
        let title: String
        var systemImage: String = "giftcard"
        let isDisabled: Bool
        let accessibilityIdentifier: String
        let action: () -> Void

        @Environment(\.themeColors) private var colors
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            Button(action: action) {
                SettingsPlanActionLabel(title: title, systemImage: systemImage)
                    .foregroundStyle(colors.primaryText)
                    .background(
                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                            .fill(colorScheme == .light ? colors.surfacePrimary : colors.fillSecondary.opacity(0.22))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                            .strokeBorder(
                                colors.border.opacity(colorScheme == .light ? 0.55 : 0.35),
                                lineWidth: ExperienceBorder.hairline
                            )
                    }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private struct SettingsPlanActionLabel: View {
        let title: String
        var isLoading: Bool = false
        var systemImage: String?

        var body: some View {
            HStack(spacing: ExperienceSpacing.xs) {
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                }
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ExperienceSpacing.sm)
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
            .experienceDashboardNestedCard(cornerRadius: ExperienceRadius.md)
        }
    }
}