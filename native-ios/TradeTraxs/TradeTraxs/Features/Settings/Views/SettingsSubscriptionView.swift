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
                productsSection
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

    private var currentPlanSection: some View {
        Section {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(viewModel.planTitle)
                        .experienceStyle(.title3, color: colors.primaryText)
                        .fontWeight(.semibold)
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
                        Text("Core journaling and community features at no cost.")
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: ExperienceSpacing.sm)
                currentPlanTrailingColumn
            }
            .padding(.vertical, ExperienceSpacing.xs)
            .accessibilityElement(children: .combine)
            .listRowBackground(colors.fillSecondary.opacity(0.28))
        } header: {
            sectionHeading("Your Current Plan")
        }
    }

    @ViewBuilder
    private var currentPlanTrailingColumn: some View {
        if viewModel.planTitle == MonetizationPlanCopy.freePlanName {
            Text("$0")
                .experienceStyle(.headline, color: colors.primaryText)
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
            return "What's Included in \(MonetizationPlanCopy.proPlanName)"
        }
        if viewModel.planTitle == MonetizationPlanCopy.freePlanName {
            return "What's Included in \(MonetizationPlanCopy.freePlanName)"
        }
        return "What's Included"
    }

    @ViewBuilder
    private var disclosuresSection: some View {
        if viewModel.status != nil {
            Section {
                disclosureRow(
                    title: includedDisclosureTitle,
                    isExpanded: showsIncludedDetails,
                    accessibilityID: "settings.subscription.included"
                ) {
                    showsIncludedDetails.toggle()
                } content: {
                    includedDetails
                }

                if viewModel.showsFreePlanDetails {
                    disclosureRow(
                        title: MonetizationPlanCopy.proEverythingInFreeHeading,
                        isExpanded: showsTraxProBenefits,
                        accessibilityID: "settings.subscription.traxproBenefits"
                    ) {
                        showsTraxProBenefits.toggle()
                    } content: {
                        proBenefitList
                    }
                }
            }
        }
    }

    private func disclosureRow<Content: View>(
        title: String,
        isExpanded: Bool,
        accessibilityID: String,
        toggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Button {
                withAnimation(ExperienceMotion.navigation) {
                    toggle()
                }
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    Text(title)
                        .experienceStyle(.body, color: colors.primaryText)
                    Spacer(minLength: ExperienceSpacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier(accessibilityID)

            if isExpanded {
                content()
                    .padding(.top, ExperienceSpacing.xxs)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private var includedDetails: some View {
        if viewModel.showsProMembership {
            proBenefitList
        } else if viewModel.showsFreePlanDetails {
            freePlanFeatureList
        } else if viewModel.showsReleaseIncludedPlanDetails {
            Text("This release includes Trade AI, analytics, and journal features at no additional cost.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var proBenefitList: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            ForEach(MonetizationPlanCopy.proPlanFeatures, id: \.self) { line in
                MonetizationPlanPresentation.BenefitRow(text: line)
            }
        }
    }

    private var freePlanFeatureList: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            ForEach(MonetizationPlanCopy.freePlanFeatures, id: \.self) { line in
                MonetizationPlanPresentation.BenefitRow(text: line)
            }
        }
    }

    @ViewBuilder
    private var productsSection: some View {
        Section {
            switch viewModel.productsState {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("Loading plans…")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
                .padding(.vertical, ExperienceSpacing.xxs)
            case .failed:
                SettingsInlineError(message: "Couldn't load App Store plans right now.") {
                    viewModel.retryLoadProducts()
                }
            case .loaded(let products):
                ForEach(products) { product in
                    planCard(product)
                }
                Button {
                    Task { await viewModel.purchaseSelectedPlan() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.actionState == .purchasing || viewModel.actionState == .synchronizing {
                            ProgressView()
                                .padding(.trailing, ExperienceSpacing.xs)
                        }
                        Text(viewModel.subscribeButtonTitle)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, ExperienceSpacing.xxs)
                }
                .disabled(viewModel.isPrimaryActionDisabled)
                .accessibilityIdentifier("settings.subscription.subscribe")
            }
        } header: {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                sectionHeading("Choose Your Plan")
                if viewModel.showsFreePlanDetails {
                    Text(viewModel.upgradeHeroTitle)
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                }
            }
        } footer: {
            if case .loaded = viewModel.productsState {
                Text(SubscriptionPresentationPolicy.autoRenewDisclosure(selectedProduct: viewModel.selectedProduct))
            }
        }
    }

    private func planCard(_ product: StoreKitTraxProProduct) -> some View {
        let isSelected = viewModel.selectedProduct?.id == product.id
        return Button {
            viewModel.selectProduct(product.id)
        } label: {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(planDuration(product))
                        .experienceStyle(.subheadline, color: colors.primaryText)
                    Text(product.displayPrice)
                        .experienceStyle(.headline, color: colors.primaryText)
                    if let offer = product.introductoryOfferSummary {
                        Text(offer)
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                Spacer(minLength: ExperienceSpacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? colors.accent : colors.tertiaryText)
            }
            .frame(minHeight: 44, alignment: .center)
            .padding(.vertical, ExperienceSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .modifier(SubscriptionPlanListRowBackground(isSelected: isSelected))
        .accessibilityIdentifier("settings.subscription.product.\(product.id)")
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
            }
            .buttonStyle(.experiencePlain)
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
                }
                .buttonStyle(.experiencePlain)
                .disabled(subscriptionFooterActionsDisabled)
                .accessibilityIdentifier("settings.subscription.restore")
            }

            if viewModel.showsRedeemOfferCode {
                MonetizationPlanPresentation.AppleOfferCodeRedemptionButton(
                    style: .settingsList,
                    isDisabled: subscriptionFooterActionsDisabled,
                    accessibilityIdentifier: "settings.subscription.redeemOfferCode"
                ) {
                    Task { await viewModel.redeemOfferCode() }
                }
            }

            compactLegalLinksRow
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
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .textCase(nil)
    }

    private func planDuration(_ product: StoreKitTraxProProduct) -> String {
        let label = product.subscriptionPeriodLabel
        return label == "Subscription" ? product.displayName : label
    }
}

/// Unselected plan rows only — avoids system grouped brown in dark mode without global UIKit appearance.
private struct SubscriptionPlanListRowBackground: ViewModifier {
    let isSelected: Bool
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if isSelected {
            content.listRowBackground(colors.accent.opacity(0.12))
        } else {
            content.experienceDashboardListRow()
        }
    }
}