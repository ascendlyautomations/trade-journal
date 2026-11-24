import SwiftUI

struct SettingsSubscriptionView: View {
    @State private var viewModel: SettingsSubscriptionViewModel
    @State private var showsIncludedDetails = false
    @State private var showsTraxProBenefits = false

    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: SettingsSubscriptionViewModel(
                billing: data.billing,
                storeKit: data.storeKitSubscriptions,
                session: data.session,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    init(viewModel: SettingsSubscriptionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            if let actionMessage = viewModel.actionMessage {
                Section {
                    SettingsIntroBlock(title: "Update", message: actionMessage)
                }
            }

            currentPlanSection
            disclosuresSection

            if viewModel.showsManageSubscription {
                manageSection
            }

            if viewModel.showsApplePurchaseSection {
                choosePlanSection
                purchaseActionsSection
            }

            subscriptionFooterSection
        }
        .listSectionSpacing(ExperienceSpacing.xxs)
        .environment(\.defaultMinListHeaderHeight, 0)
        .experienceInsetGroupedListStyle(pageBackground: true)
        .experienceNavigationTitle("Plan")
        .overlay {
            if viewModel.isLoading, viewModel.status == nil {
                ProgressView()
            }
        }
        .onAppear {
            showsIncludedDetails = false
            showsTraxProBenefits = false
            viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { notification in
            guard let refreshed = notification.object as? BillingStatus else { return }
            viewModel.applyForegroundEntitlementRefresh(refreshed)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .accessibilityIdentifier("settings.subscription")
    }

    // MARK: - Current plan

    private var currentPlanSection: some View {
        Section {
            currentPlanCard
                .listRowInsets(settingsPlanCardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: {
            sectionHeading(MonetizationPlanCopy.settingsCurrentPlanTitle)
        }
    }

    private var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                Text(viewModel.planTitle)
                    .experienceStyle(.title3, color: colors.primaryText)
                    .fontWeight(.semibold)
                Spacer(minLength: ExperienceSpacing.sm)
                currentPlanTrailingColumn
            }

            if viewModel.isRefreshingEntitlements {
                HStack(spacing: ExperienceSpacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating plan…")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            } else if let renewal = viewModel.renewalDetail, viewModel.showsProMembership {
                Text(renewal)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if viewModel.showsFreePlanDetails {
                Text(MonetizationPlanCopy.freePlanShortDescription)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if viewModel.showsReleaseIncludedPlanDetails {
                Text("This release includes Trade AI, analytics, and journal features at no additional cost.")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var currentPlanTrailingColumn: some View {
        if viewModel.planTitle == MonetizationPlanCopy.freePlanName {
            Text(MonetizationPlanCopy.freePlanPriceLabel)
                .experienceStyle(.headline, color: colors.primaryText)
                .fontWeight(.bold)
                .monospacedDigit()
        } else if viewModel.showsReleaseIncludedPlanDetails {
            Text("Included")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
        } else if viewModel.showsActiveAppleBillingDetails {
            VStack(alignment: .trailing, spacing: ExperienceSpacing.xxs) {
                if let price = viewModel.activePlanStoreKitPrice {
                    Text(price)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.trailing)
                }
                if let interval = viewModel.activePlanBillingIntervalLabel {
                    Text(interval)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
        } else if viewModel.showsProMembership {
            Text(nonAppleProTrailingStatus)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private var nonAppleProTrailingStatus: String {
        if let billing = compactBillingStatus {
            return billing
        }
        return "Active"
    }

    private var compactBillingStatus: String? {
        guard let detail = viewModel.billingDetail else { return nil }
        let prefix = "Plan: "
        if detail.hasPrefix(prefix) {
            return String(detail.dropFirst(prefix.count))
        }
        return detail
    }

    private var includedDisclosureTitle: String {
        if viewModel.showsProMembership {
            return MonetizationPlanCopy.settingsTraxProIncludedTitle
        }
        if viewModel.planTitle == MonetizationPlanCopy.freePlanName {
            return MonetizationPlanCopy.settingsFreePlanIncludedTitle
        }
        return "What's Included"
    }

    // MARK: - Benefits

    @ViewBuilder
    private var disclosuresSection: some View {
        if viewModel.status != nil {
            Section {
                planBenefitDisclosureCard(
                    title: includedDisclosureTitle,
                    isExpanded: showsIncludedDetails,
                    accessibilityID: "settings.subscription.included"
                ) {
                    showsIncludedDetails.toggle()
                } content: {
                    includedDetails
                }

                if viewModel.showsFreePlanDetails {
                    planBenefitDisclosureCard(
                        title: MonetizationPlanCopy.settingsTraxProUnlockTitle,
                        isExpanded: showsTraxProBenefits,
                        accessibilityID: "settings.subscription.traxproBenefits"
                    ) {
                        showsTraxProBenefits.toggle()
                    } content: {
                        MonetizationPlanPresentation.PlanFeatureSummaryList(
                            highlights: MonetizationPlanCopy.traxProUnlockHighlights
                        )
                    }
                }
            }
        }
    }

    private func planBenefitDisclosureCard<Content: View>(
        title: String,
        isExpanded: Bool,
        accessibilityID: String,
        toggle: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        MonetizationPlanPresentation.DisclosureToggle(
            title: title,
            isExpanded: isExpanded,
            accessibilityID: accessibilityID,
            onToggle: toggle,
            content: content
        )
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
        .listRowInsets(settingsPlanCardInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var includedDetails: some View {
        if viewModel.showsProMembership {
            MonetizationPlanPresentation.PlanFeatureSummaryList(
                highlights: MonetizationPlanCopy.traxProUnlockHighlights
            )
        } else if viewModel.showsFreePlanDetails {
            MonetizationPlanPresentation.PlanFeatureSummaryList(
                highlights: MonetizationPlanCopy.freePlanSummaryHighlights
            )
        } else if viewModel.showsReleaseIncludedPlanDetails {
            Text("This release includes Trade AI, analytics, and journal features at no additional cost.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Subscription products

    @ViewBuilder
    private var choosePlanSection: some View {
        Section {
            switch viewModel.productsState {
            case .idle, .loading:
                HStack(spacing: ExperienceSpacing.sm) {
                    ProgressView()
                    Text("Loading plans…")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
                .listRowInsets(settingsPlanCardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            case .failed:
                SettingsInlineError(message: "Couldn't load App Store plans right now.") {
                    viewModel.retryLoadProducts()
                }
                .listRowInsets(settingsPlanCardInsets)
                .listRowBackground(Color.clear)
            case .loaded(let products):
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(products) { product in
                        MonetizationPlanPresentation.SubscriptionPlanOptionRow(
                            product: product,
                            isSelected: viewModel.selectedProduct?.id == product.id,
                            accessibilityIdentifier: "settings.subscription.product.\(product.id)"
                        ) {
                            viewModel.selectProduct(product.id)
                        }
                    }
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
                .listRowInsets(settingsPlanCardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(MonetizationPlanCopy.settingsChoosePlanTitle)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                if viewModel.showsFreePlanDetails {
                    Text(viewModel.upgradeHeroTitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            }
            .textCase(nil)
            .padding(.bottom, ExperienceSpacing.xxs)
        }
    }

    @ViewBuilder
    private var purchaseActionsSection: some View {
        if case .loaded = viewModel.productsState {
            Section {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        MonetizationPlanPresentation.SettingsPlanPrimaryUpgradeButton(
                            title: viewModel.subscribeButtonTitle,
                            isLoading: viewModel.actionState == .purchasing
                                || viewModel.actionState == .synchronizing,
                            isDisabled: viewModel.isPrimaryActionDisabled,
                            accessibilityIdentifier: "settings.subscription.subscribe"
                        ) {
                            Task { await viewModel.purchaseSelectedPlan() }
                        }

                        if viewModel.showsRedeemOfferCode {
                            Divider()
                                .overlay(colors.separator.opacity(0.35))

                            MonetizationPlanPresentation.SettingsPlanSecondaryActionButton(
                                title: MonetizationPlanCopy.redeemAppleOfferCodeButtonTitle,
                                isDisabled: subscriptionFooterActionsDisabled,
                                accessibilityIdentifier: "settings.subscription.redeemOfferCode"
                            ) {
                                Task { await viewModel.redeemOfferCode() }
                            }
                        }
                    }

                    if let footnote = viewModel.upgradePostTrialFootnote {
                        Text(footnote)
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(SubscriptionPresentationPolicy.autoRenewDisclosure(selectedProduct: viewModel.selectedProduct))
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.subscription.autoRenew")
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
                .listRowInsets(settingsPlanCardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private var manageSection: some View {
        Section {
            Button {
                Task { await viewModel.manageSubscription() }
            } label: {
                SettingsPrimaryActionLabel(
                    title: "Manage Subscription",
                    systemImage: "arrow.up.right.square"
                )
                .padding(.horizontal, ExperienceSpacing.md)
            }
            .buttonStyle(.experiencePlain)
            .listRowInsets(settingsPlanCardInsets)
        }
    }

    private var subscriptionFooterSection: some View {
        Section {
            if viewModel.showsRestorePurchases {
                Button {
                    Task { await viewModel.restorePurchases() }
                } label: {
                    SettingsPrimaryActionLabel(
                        title: viewModel.actionState == .restoring ? "Restoring…" : "Restore Purchases",
                        systemImage: "arrow.clockwise"
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }
                .buttonStyle(.experiencePlain)
                .disabled(subscriptionFooterActionsDisabled)
                .listRowInsets(settingsPlanCardInsets)
                .accessibilityIdentifier("settings.subscription.restore")
            }

            compactLegalLinksRow
                .listRowInsets(settingsPlanCardInsets)
        }
    }

    private var subscriptionFooterActionsDisabled: Bool {
        viewModel.actionState == .restoring
            || viewModel.actionState == .purchasing
            || viewModel.actionState == .synchronizing
    }

    private var compactLegalLinksRow: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Spacer(minLength: 0)
            Button {
                openURL(LegalDocuments.privacy)
            } label: {
                Text("Privacy Policy")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("settings.subscription.privacy")

            Text("•")
                .experienceStyle(.footnote, color: colors.tertiaryText)

            Button {
                openURL(LegalDocuments.terms)
            } label: {
                Text("Terms of Use")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("settings.subscription.terms")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .textCase(nil)
    }

    private var settingsPlanCardInsets: EdgeInsets {
        SettingsListLayout.groupedCardRowInsets
    }
}