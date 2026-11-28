import SwiftUI

struct PostOnboardingPlanSelectionView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let onContinueFree: () -> Void

    @State private var viewModel: SettingsSubscriptionViewModel
    @State private var creatorCode = ""
    @State private var showsCreatorPromoField = false
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        onContinueFree: @escaping () -> Void
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.onContinueFree = onContinueFree
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
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    header
                    if paymentsEnabled {
                        if viewModel.showsApplePurchaseSection || viewModel.productsState == .loading {
                            proSection
                        } else if viewModel.showsProMembership {
                            activeProSection
                        }
                    } else {
                        proSectionPaymentsPaused
                    }
                    if !viewModel.showsProMembership {
                        freeCard
                    }
                    creatorPromoSection
                }
                .experiencePadding(.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .experienceScreenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        onContinueFree()
                    }
                }
            }
            .experienceNavigationTitle("Choose Your Plan")
        }
        .interactiveDismissDisabled(true)
        .onAppear { viewModel.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { notification in
            guard let refreshed = notification.object as? BillingStatus else { return }
            viewModel.applyForegroundEntitlementRefresh(refreshed)
            if refreshed.hasTraxProAccess {
                onContinueFree()
            }
        }
        .accessibilityIdentifier("postOnboarding.planSelection")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Welcome to TradeTraxs")
                .experienceStyle(.title2, color: colors.primaryText)
                .fontWeight(.bold)
            Text("Start on Free, or unlock TraxsPro for advanced analytics, reports, AI coaching, and more.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let message = viewModel.actionMessage ?? viewModel.errorMessage {
                Text(message)
                    .experienceStyle(.footnote, color: viewModel.errorMessage != nil ? colors.error : colors.secondaryText)
            }
        }
    }

    private var freeCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Continue with Free")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Journal trades, explore the community, and grow with essential tools.")
                .experienceStyle(.footnote, color: colors.secondaryText)
            ExperienceButton(
                title: "Continue with Free",
                kind: .secondary,
                accessibilityIdentifier: "postOnboarding.continueFree",
                action: onContinueFree
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .planSelectionCard()
    }

    @ViewBuilder
    private var proSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Get TraxsPro")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(viewModel.upgradeHeroTitle)
                .experienceStyle(.footnote, color: colors.secondaryText)

            switch viewModel.productsState {
            case .idle, .loading:
                HStack(spacing: ExperienceSpacing.sm) {
                    ExperienceIndeterminateProgress()
                    Text("Loading App Store plans…")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            case .failed:
                SettingsInlineError(message: "Couldn't load plans right now.") {
                    viewModel.retryLoadProducts()
                }
            case .loaded(let products):
                ForEach(products) { product in
                    planRow(product)
                }
                ExperienceButton(
                    title: viewModel.subscribeButtonTitle,
                    kind: .primary,
                    isEnabled: !viewModel.isPrimaryActionDisabled,
                    isLoading: viewModel.actionState == .purchasing || viewModel.actionState == .synchronizing
                ) {
                    Task { await viewModel.purchaseSelectedPlan() }
                }
                .disabled(viewModel.isPrimaryActionDisabled)

                appleOfferCodeRow
                restorePurchasesRow
            }

            if case .loaded = viewModel.productsState {
            } else {
                appleOfferCodeRow
                restorePurchasesRow
            }
        }
        .planSelectionCard()
    }

    @ViewBuilder
    private var restorePurchasesRow: some View {
        if viewModel.showsRestorePurchases {
            Button {
                Task { await viewModel.restorePurchases() }
            } label: {
                SettingsPrimaryActionLabel(
                    title: viewModel.actionState == .restoring ? "Restoring…" : "Restore Purchases",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.experiencePlain)
            .disabled(viewModel.actionState == .restoring)
        }
    }

    private var paymentsEnabled: Bool {
        IosSubscriptionReleaseConfiguration.iosPaywallEnabled
    }

    private var activeProSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("You're on TraxsPro")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Your TraxsPro access stays active. Continue into the app when you're ready.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            let detail = viewModel.membershipSummaryFooter
            if detail != "–" {
                Text(detail)
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            ExperienceButton(
                title: "Continue",
                kind: .secondary,
                accessibilityIdentifier: "postOnboarding.continueFree",
                action: onContinueFree
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .planSelectionCard()
    }

    private var proSectionPaymentsPaused: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Get TraxsPro")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(
                "In-app purchasing is temporarily unavailable in this build. "
                    + "Choosing Continue below will not change your plan. "
                    + "When subscriptions reopen, you can upgrade from Settings."
            )
            .experienceStyle(.footnote, color: colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                ForEach(viewModel.traxProFeatureHighlights, id: \.self) { line in
                    Text("• \(line)")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
            appleOfferCodeRow
            restorePurchasesRow
        }
        .planSelectionCard()
    }

    @ViewBuilder
    private var appleOfferCodeRow: some View {
        if viewModel.showsRedeemOfferCode {
            MonetizationPlanPresentation.AppleOfferCodeRedemptionButton(
                style: .settingsList,
                isDisabled: !paymentsEnabled || viewModel.actionState != .idle,
                accessibilityIdentifier: "postOnboarding.redeemOfferCode",
                paymentsPausedFootnote: paymentsEnabled
                    ? nil
                    : MonetizationPlanCopy.offerCodeRedemptionPausedFootnote
            ) {
                guard paymentsEnabled else { return }
                Task { await viewModel.redeemOfferCode() }
            }
        }
    }

    @ViewBuilder
    private var creatorPromoSection: some View {
        if IosSubscriptionReleaseConfiguration.iosCreatorPromoRedemptionEnabled {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text("Have a Promo Code?")
                    .experienceStyle(.headline, color: colors.primaryText)
                if showsCreatorPromoField {
                    TextField("Creator access code", text: $creatorCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button {
                        Task { await viewModel.redeemCreatorAccessCode(creatorCode) }
                    } label: {
                        SettingsPrimaryActionLabel(
                            title: "Redeem TradeTraxs Code",
                            systemImage: "ticket"
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .disabled(creatorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button {
                        showsCreatorPromoField = true
                    } label: {
                        SettingsPrimaryActionLabel(
                            title: "Enter TradeTraxs Code",
                            systemImage: "ticket"
                        )
                    }
                    .buttonStyle(.experiencePlain)
                }
            }
            .planSelectionCard()
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
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? colors.accent : colors.tertiaryText)
            }
        }
        .buttonStyle(.experiencePlain)
    }

}

private extension View {
    func planSelectionCard() -> some View {
        padding(ExperienceSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
    }
}