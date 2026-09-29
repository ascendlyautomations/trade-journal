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
                legalSection
            }

            if viewModel.showsRestorePurchases {
                restoreSection
            }
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
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(viewModel.planTitle)
                        .experienceStyle(.headline, color: colors.primaryText)
                    if viewModel.isRefreshingEntitlements {
                        HStack(spacing: ExperienceSpacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating plan…")
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }
                    }
                }
                Spacer(minLength: ExperienceSpacing.sm)
                if !currentPlanAmount.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(currentPlanAmount)
                            .experienceStyle(.headline, color: colors.primaryText)
                            .multilineTextAlignment(.trailing)
                        if let detail = currentPlanDetail {
                            Text(detail)
                                .experienceStyle(.caption, color: colors.secondaryText)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .padding(.vertical, ExperienceSpacing.xxs)
            .accessibilityElement(children: .combine)
        } header: {
            sectionHeading("Your Current Plan")
        }
    }

    private var currentPlanAmount: String {
        if viewModel.showsProMembership {
            if let storePrice = currentStoreKitPrice {
                return storePrice
            }
            if let billing = compactBillingStatus {
                return billing
            }
            return "Active"
        }
        if viewModel.planTitle == "Free" {
            return "$0"
        }
        if viewModel.showsReleaseIncludedPlanDetails {
            return "Included"
        }
        return ""
    }

    /// StoreKit `displayPrice` for the entitled product, only when that product is already loaded.
    private var currentStoreKitPrice: String? {
        guard let productID = viewModel.status?.appleProductID,
              case .loaded(let products) = viewModel.productsState,
              let product = products.first(where: { $0.id == productID }) else {
            return nil
        }
        if let suffix = pricePeriodSuffix(for: viewModel.status?.billingInterval) {
            return "\(product.displayPrice)/\(suffix)"
        }
        return product.displayPrice
    }

    private var compactBillingStatus: String? {
        guard let detail = viewModel.billingDetail else { return nil }
        let prefix = "Plan: "
        if detail.hasPrefix(prefix) {
            return String(detail.dropFirst(prefix.count))
        }
        return detail
    }

    private var currentPlanDetail: String? {
        guard viewModel.showsProMembership else { return nil }
        return viewModel.renewalDetail
    }

    private func pricePeriodSuffix(for interval: BillingInterval?) -> String? {
        switch interval {
        case .monthly:
            return "mo"
        case .sixMonth:
            return "6 mo"
        case .yearly:
            return "yr"
        case nil:
            return nil
        }
    }

    private var includedDisclosureTitle: String {
        if viewModel.showsProMembership {
            return "What's Included in TraxPro"
        }
        if viewModel.planTitle == "Free" {
            return "What's Included in Free"
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
                        title: "With TraxPro",
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
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityID)

            if isExpanded {
                content()
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private var includedDetails: some View {
        if viewModel.showsProMembership {
            proBenefitList
        } else if viewModel.showsFreePlanDetails, let status = viewModel.status {
            freeLimitList(status)
        } else if viewModel.showsReleaseIncludedPlanDetails {
            Text("This release includes Trade AI, analytics, and journal features at no additional cost.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var proBenefitList: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            benefitRow(
                title: "Trades",
                detail: "No daily trade limit."
            )
            benefitRow(
                title: "Trading accounts",
                detail: "No limit on active trading accounts."
            )
            benefitRow(
                title: "Advanced analytics",
                detail: "Advanced psychology and analytics tools."
            )
            benefitRow(
                title: "Trade AI",
                detail: "Trade AI analysis on your trades."
            )
        }
    }

    private func freeLimitList(_ status: BillingStatus) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            featureRow(title: "Trades", detail: "\(dailyTrades(status)) a day")
            featureRow(title: "Posts", detail: "\(dailyPosts(status)) a day")
            featureRow(title: "Clips", detail: "\(FreeTierPolicy.dailyReelLimit) a day")
            featureRow(title: "Messages", detail: "\(dailyMessages(status)) a day")
            featureRow(title: "Accounts", detail: "\(activeAccounts(status)) active")
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
            sectionHeading("Choose Your Plan")
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
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? colors.accent.opacity(0.12) : nil)
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
            .buttonStyle(.plain)
        }
    }

    private var legalSection: some View {
        Section {
            legalLink(title: "Terms of Use", url: LegalDocuments.terms)
            legalLink(title: "Privacy Policy", url: LegalDocuments.privacy)
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                Task { await viewModel.restorePurchases() }
            } label: {
                SettingsPrimaryActionLabel(
                    title: viewModel.actionState == .restoring ? "Restoring…" : "Restore Purchases",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.actionState == .restoring || viewModel.actionState == .purchasing)
            .accessibilityIdentifier("settings.subscription.restore")
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .textCase(nil)
    }

    private func featureRow(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 14, alignment: .center)
            Text(title)
                .experienceStyle(.subheadline, color: colors.primaryText)
            Spacer(minLength: ExperienceSpacing.xs)
            Text(detail)
                .experienceStyle(.caption, color: colors.secondaryText)
        }
    }

    private func benefitRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                Text(detail)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legalLink(title: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            SettingsNavigationRow(title: title, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func dailyTrades(_ status: BillingStatus) -> Int {
        status.dailyTradeLimit ?? FreeTierPolicy.dailyTradeLimit
    }

    private func dailyPosts(_ status: BillingStatus) -> Int {
        status.dailyPostLimit ?? FreeTierPolicy.dailyPostLimit
    }

    private func dailyMessages(_ status: BillingStatus) -> Int {
        status.dailyMessageLimit ?? FreeTierPolicy.dailyDirectMessageLimit
    }

    private func activeAccounts(_ status: BillingStatus) -> Int {
        status.maxTradeEntryAccounts ?? FreeTierPolicy.maxTradeEntryAccounts
    }

    private func planDuration(_ product: StoreKitTraxProProduct) -> String {
        let label = product.subscriptionPeriodLabel
        return label == "Subscription" ? product.displayName : label
    }
}
