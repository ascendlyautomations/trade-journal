import SwiftUI

/// Limit- and feature-triggered upgrade sheet, reuses Settings subscription purchase flow.
struct ProUpgradeGateSheet: View {
    let reason: ProGateReason
    @Bindable var coordinator: ProUpgradeCoordinator
    @State private var viewModel: SettingsSubscriptionViewModel
    @State private var showsAllPlans = false
    @State private var showsAllBenefits = false

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(
        reason: ProGateReason,
        coordinator: ProUpgradeCoordinator,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.reason = reason
        self.coordinator = coordinator
        _viewModel = State(
            initialValue: SettingsSubscriptionViewModel(
                billing: data.billing,
                storeKit: data.storeKitSubscriptions,
                session: data.session,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    heroHeader
                    limitContextBlock
                    statusFeedback
                    highlightBenefits
                    improvementDisclosure
                    MonetizationPlanPresentation.SelectedSubscriptionPriceCard(
                        product: viewModel.selectedProduct
                    )
                    if let footnote = viewModel.upgradePostTrialFootnote,
                       viewModel.selectedProduct?.hasEligibleIntroductoryOffer == true
                    {
                        Text(footnote)
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    primaryActions
                    if showsAllPlans {
                        plansBlock
                    }
                    legalDisclosure
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.md)
            }
            .background(colors.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        coordinator.dismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.secondaryText)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("proUpgrade.close")
                }
                if coordinator.showsPreviewProAction(for: reason),
                   let previewFeature = coordinator.resolvedPreviewFeature(for: reason)
                {
                    ToolbarItem(placement: .topBarTrailing) {
                        MonetizationPlanPresentation.ProUpgradePreviewProToolbarButton(
                            previewFeature: previewFeature,
                            accessibilityIdentifier: "proUpgrade.previewPro"
                        ) {
                            ExperienceHaptics.play(.selection)
                            TraxsProPreviewCoordinator.shared.schedulePreviewAfterPaywallDismiss(
                                feature: previewFeature,
                                entryPoint: .proUpgradeSheet
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { notification in
            guard let refreshed = notification.object as? BillingStatus else { return }
            viewModel.applyForegroundEntitlementRefresh(refreshed)
            if refreshed.hasTraxProAccess {
                coordinator.completePurchaseIfPro(active: true)
                dismiss()
            }
        }
    }

    private var heroHeader: some View {
        Text(MonetizationPlanCopy.paywallUnlockTitle)
            .experienceStyle(.title2, color: colors.primaryText)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var limitContextBlock: some View {
        if case .limit = reason {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text(reason.sheetTitle)
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .fontWeight(.semibold)
                Text(reason.detailMessage)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason.upsellFooter)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ReportDetailInsetSurface(cornerRadius: ExperienceRadius.md))
        }
    }

    @ViewBuilder
    private var statusFeedback: some View {
        if viewModel.errorMessage != nil || viewModel.actionMessage != nil {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                if let error = viewModel.errorMessage {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
                if let actionMessage = viewModel.actionMessage {
                    Text(actionMessage)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var highlightBenefits: some View {
        MonetizationPlanPresentation.ProMarketingFeatureList(compact: true, showsDividers: false)
    }

    private var improvementDisclosure: some View {
        MonetizationPlanPresentation.DisclosureToggle(
            title: MonetizationPlanCopy.paywallImprovementSectionTitle,
            isExpanded: showsAllBenefits,
            accessibilityID: "proUpgrade.improvementSection"
        ) {
            showsAllBenefits.toggle()
        } content: {
            MonetizationPlanPresentation.ProMarketingOutcomeList(compact: true)
                .padding(.top, ExperienceSpacing.xxs)
        }
    }

    private var primaryActions: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            Button {
                Task { await viewModel.purchaseSelectedPlan() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.actionState == .purchasing || viewModel.actionState == .synchronizing {
                        ExperienceIndeterminateProgress()
                            .padding(.trailing, ExperienceSpacing.xs)
                    }
                    Text(viewModel.upgradePrimaryButtonTitle)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, ExperienceSpacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(viewModel.isPrimaryActionDisabled)
            .accessibilityIdentifier("proUpgrade.primaryPurchase")

            if viewModel.showsRedeemOfferCode {
                MonetizationPlanPresentation.AppleOfferCodeRedemptionButton(
                    style: .paywall,
                    isDisabled: viewModel.actionState != .idle,
                    accessibilityIdentifier: "proUpgrade.redeemOfferCode"
                ) {
                    Task { await viewModel.redeemOfferCode() }
                }
            }

            Button {
                withAnimation(ExperienceMotion.navigation) {
                    showsAllPlans.toggle()
                }
                if showsAllPlans {
                    viewModel.retryLoadProducts()
                }
            } label: {
                Text(showsAllPlans ? "Hide Plans" : "View Plans")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var legalDisclosure: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(SubscriptionPresentationPolicy.autoRenewDisclosure(selectedProduct: viewModel.selectedProduct))
                .experienceStyle(.caption, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("proUpgrade.autoRenew")

            HStack(spacing: ExperienceSpacing.xs) {
                Spacer(minLength: 0)
                Button {
                    openURL(LegalDocuments.privacy)
                } label: {
                    Text("Privacy Policy")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("proUpgrade.privacy")

                Text("•")
                    .experienceStyle(.footnote, color: colors.tertiaryText)

                Button {
                    openURL(LegalDocuments.terms)
                } label: {
                    Text("Terms of Use")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("proUpgrade.terms")

                Spacer(minLength: 0)
            }
        }
        .padding(.top, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private var plansBlock: some View {
        switch viewModel.productsState {
        case .idle, .loading:
            ExperienceLoadingSpinner(message: "Loading plans…")
        case .failed:
            SettingsInlineError(message: "Couldn't load App Store plans right now.") {
                viewModel.retryLoadProducts()
            }
        case .loaded(let products):
            VStack(spacing: ExperienceSpacing.sm) {
                ForEach(products) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: StoreKitTraxProProduct) -> some View {
        let isSelected = viewModel.selectedProduct?.id == product.id
        return Button {
            viewModel.selectProduct(product.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(product.subscriptionPeriodLabel)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                    Text(product.displayPrice)
                        .experienceStyle(.headline, color: colors.primaryText)
                    if let offer = product.introductoryOfferSummary {
                        Text(offer)
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? colors.accent : colors.tertiaryText)
            }
            .padding(ExperienceSpacing.sm)
            .modifier(ProUpgradePlanRowSurface(isSelected: isSelected))
        }
        .buttonStyle(.experiencePlain)
    }
}

enum ProUpgradeMarketing {
    static var benefitLines: [String] { MonetizationPlanCopy.proPlanFeatures }
}

private struct ProUpgradePlanRowSurface: ViewModifier {
    var isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .light {
            if isSelected {
                content
                    .background(colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                            .strokeBorder(
                                colors.accent.opacity(0.55),
                                lineWidth: ExperienceBorder.hairline
                            )
                    }
            } else {
                content.modifier(ReportDetailInsetSurface(cornerRadius: ExperienceRadius.sm))
            }
        } else {
            content.background(
                colors.fillSecondary.opacity(isSelected ? 0.45 : 0.22),
                in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            )
        }
    }
}