import SwiftUI

struct SettingsSubscriptionView: View {
    @State private var viewModel: SettingsSubscriptionViewModel
    @State private var showsIncludedDetails = false
    @State private var showsTraxProBenefits = false
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
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

            unifiedCurrentPlanSection

            if viewModel.showsManageSubscription {
                manageSection
            }

            if viewModel.showsApplePurchaseSection {
                unifiedChoosePlanSection
            }

            subscriptionFooterSection
        }
        .listSectionSpacing(0)
        .contentMargins(.top, SettingsPlanPageLayout.exteriorVerticalGap, for: .scrollContent)
        .environment(\.defaultMinListHeaderHeight, 0)
        .experienceInsetGroupedListStyle(pageBackground: true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsPersistentFreePlanUpgradeFooter {
                freePlanPersistentUpgradeFooter
                    .padding(.top, ExperienceSpacing.xxs)
                    .background(colors.groupedBackground)
            }
        }
        .experienceNavigationTitle("Plan")
        .overlay {
            if viewModel.isLoading, viewModel.status == nil {
                ExperienceIndeterminateProgress()
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

    // MARK: - Current plan (unified card)

    private var unifiedCurrentPlanSection: some View {
        Section {
            unifiedCurrentPlanCard
                .listRowInsets(settingsPlanCardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var unifiedCurrentPlanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading(MonetizationPlanCopy.settingsCurrentPlanTitle)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.md)
                .padding(.bottom, ExperienceSpacing.xs)

            currentPlanSummaryBlock
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.bottom, ExperienceSpacing.md)

            if viewModel.status != nil {
                settingsPlanInternalDivider

                planBenefitDisclosureRow(
                    title: includedDisclosureTitle,
                    isExpanded: showsIncludedDetails,
                    accessibilityID: "settings.subscription.included"
                ) {
                    showsIncludedDetails.toggle()
                } content: {
                    includedDetails
                }

                if viewModel.showsFreePlanDetails {
                    settingsPlanInternalDivider

                    planBenefitDisclosureRow(
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsPlanCardSurface(cornerRadii: .all(ExperienceRadius.md)))
        .accessibilityElement(children: .contain)
    }

    private var currentPlanSummaryBlock: some View {
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
                    ExperienceIndeterminateProgress()
                        .controlSize(.small)
                    Text("Updating plan…")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            } else if let renewal = viewModel.renewalDetail, viewModel.showsProMembership {
                Text(renewal)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if viewModel.showsLifetimeGrantedAppreciationMessage {
                Text(MonetizationPlanCopy.lifetimeGrantedTraxProAppreciation)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.subscription.lifetimeAppreciation")
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

    private func planBenefitDisclosureRow<Content: View>(
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
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Choose plan (unified card)

    private var showsPersistentFreePlanUpgradeFooter: Bool {
        viewModel.showsFreePlanDetails && viewModel.showsApplePurchaseSection
    }

    private var unifiedChoosePlanSection: some View {
        Section {
            unifiedChoosePlanCard
                .listRowInsets(settingsPlanCardInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var unifiedChoosePlanCard: some View {
        let connectsFooter = showsPersistentFreePlanUpgradeFooter
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(MonetizationPlanCopy.settingsChoosePlanTitle)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                if viewModel.showsFreePlanDetails {
                    Text(viewModel.upgradeHeroTitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.sm)

            settingsPlanInternalDivider

            choosePlanProductsBlock
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)

            if case .loaded = viewModel.productsState {
                settingsPlanInternalDivider

                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    if !showsPersistentFreePlanUpgradeFooter {
                        freePlanUpgradeActionButtons
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
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .padding(.bottom, connectsFooter ? ExperienceSpacing.xs : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(
            SettingsPlanCardSurface(
                cornerRadii: connectsFooter
                    ? .connectedToStickyFooter
                    : .all(ExperienceRadius.md)
            )
        )
    }

    @ViewBuilder
    private var choosePlanProductsBlock: some View {
        switch viewModel.productsState {
        case .idle, .loading:
            HStack(spacing: ExperienceSpacing.sm) {
                ExperienceIndeterminateProgress()
                Text("Loading plans…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            SettingsInlineError(message: "Couldn't load App Store plans right now.") {
                viewModel.retryLoadProducts()
            }
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        SettingsPlanPageLayout.cardRowInsets
    }

    private var freePlanUpgradeActionButtons: some View {
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
    }

    private var freePlanPersistentUpgradeFooter: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                settingsPlanInternalDivider
                freePlanUpgradeActionButtons
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, settingsPlanListHorizontalInset)
        .modifier(SettingsPlanCardSurface(cornerRadii: .stickyFooter))
        .accessibilityIdentifier("settings.subscription.persistentFooter")
    }

    private var settingsPlanInternalDivider: some View {
        Rectangle()
            .fill(colors.separator.opacity(colorScheme == .light ? 0.35 : 0.45))
            .frame(height: ExperienceBorder.hairline)
    }

    /// Aligns sticky footer edges with inset-grouped list cards.
    private var settingsPlanListHorizontalInset: CGFloat {
        ExperienceSpacing.lg
    }
}

// MARK: - Plan page list spacing (header ↔ cards ↔ cards)

private enum SettingsPlanPageLayout {
    /// Matches the gap from the nav title to the first card and between stacked plan cards.
    static let exteriorVerticalGap = ExperienceSpacing.xxs

    static var cardRowInsets: EdgeInsets {
        EdgeInsets(
            top: exteriorVerticalGap,
            leading: 0,
            bottom: exteriorVerticalGap,
            trailing: 0
        )
    }
}

// MARK: - Plan card chrome

private struct SettingsPlanCardCornerRadii: Equatable {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat

    static func all(_ radius: CGFloat) -> Self {
        Self(topLeading: radius, topTrailing: radius, bottomLeading: radius, bottomTrailing: radius)
    }

    static var connectedToStickyFooter: Self {
        Self(
            topLeading: ExperienceRadius.md,
            topTrailing: ExperienceRadius.md,
            bottomLeading: 0,
            bottomTrailing: 0
        )
    }

    static var stickyFooter: Self {
        Self(topLeading: 0, topTrailing: 0, bottomLeading: ExperienceRadius.md, bottomTrailing: ExperienceRadius.md)
    }

    var asRectangleCornerRadii: RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: topLeading,
            bottomLeading: bottomLeading,
            bottomTrailing: bottomTrailing,
            topTrailing: topTrailing
        )
    }
}

private struct SettingsPlanCardSurface: ViewModifier {
    var cornerRadii: SettingsPlanCardCornerRadii

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            let shape = UnevenRoundedRectangle(
                cornerRadii: cornerRadii.asRectangleCornerRadii,
                style: .continuous
            )
            shape
                .fill(colors.surfacePrimary)
                .overlay {
                    shape.strokeBorder(
                        borderColor,
                        lineWidth: ExperienceBorder.hairline
                    )
                }
                .shadow(
                    color: shadowColor,
                    radius: shadowRadius,
                    x: 0,
                    y: shadowY
                )
        }
    }

    private var borderColor: Color {
        if colorScheme == .light {
            return colors.border.opacity(ExperienceDashboardSurface.LightChrome.borderOpacity)
        }
        return colors.border.opacity(ExperienceDashboardSurface.DarkChrome.borderOpacity)
    }

    private var shadowColor: Color {
        guard colorScheme == .light, cornerRadii.bottomLeading > 0 else { return .clear }
        return colors.surfaceOverlay.opacity(ExperienceDashboardSurface.LightChrome.shadowOpacity)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .light && cornerRadii.bottomLeading > 0
            ? ExperienceDashboardSurface.LightChrome.shadowRadius
            : 0
    }

    private var shadowY: CGFloat {
        colorScheme == .light && cornerRadii.bottomLeading > 0
            ? ExperienceDashboardSurface.LightChrome.shadowY
            : 0
    }
}