import SwiftUI

/// Limit- and feature-triggered upgrade sheet — reuses Settings subscription purchase flow.
struct ProUpgradeGateSheet: View {
    let reason: ProGateReason
    @Bindable var coordinator: ProUpgradeCoordinator
    @State private var viewModel: SettingsSubscriptionViewModel
    @State private var showsAllPlans = false

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

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
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    headerBlock
                    benefitList
                    primaryActions
                    if showsAllPlans {
                        plansBlock
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.lg)
            }
            .background(colors.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        coordinator.dismiss()
                        dismiss()
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

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(reason.sheetTitle)
                .experienceStyle(.title2, color: colors.primaryText)
                .fontWeight(.bold)
            Text(reason.detailMessage)
                .experienceStyle(.body, color: colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if case .limit = reason {
                Text(reason.upsellFooter)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote = viewModel.upgradePostTrialFootnote, viewModel.selectedProduct?.hasEligibleIntroductoryOffer == true {
                Text(footnote)
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            if let error = viewModel.errorMessage {
                SettingsInlineError(message: error) {
                    Task { await viewModel.refresh() }
                }
            }
            if let actionMessage = viewModel.actionMessage {
                Text(actionMessage)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        }
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("TradeTraxs Pro")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Unlock everything in TradeTraxs.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
            ForEach(ProUpgradeMarketing.benefitLines, id: \.self) { line in
                HStack(alignment: .top, spacing: ExperienceSpacing.xs) {
                    Text("✓")
                        .experienceStyle(.body, color: colors.accent)
                    Text(line)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                        ProgressView()
                            .padding(.trailing, ExperienceSpacing.xs)
                    }
                    Text(viewModel.upgradePrimaryButtonTitle)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, ExperienceSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isPrimaryActionDisabled)
            .accessibilityIdentifier("proUpgrade.primaryPurchase")

            Button {
                withAnimation(ExperienceMotion.navigation) {
                    showsAllPlans.toggle()
                }
                if showsAllPlans {
                    viewModel.retryLoadProducts()
                }
            } label: {
                Text(showsAllPlans ? "Hide Plans" : "View Pro Plans")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var plansBlock: some View {
        switch viewModel.productsState {
        case .idle, .loading:
            ProgressView("Loading plans…")
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
            .background(colors.backgroundSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

enum ProUpgradeMarketing {
    static let benefitLines: [String] = [
        "Unlimited manual trades",
        "Unlimited trading accounts",
        "Copy Trading",
        "AI Trade Analyst",
        "Backtest Lab",
        "Prop Firm Mode",
        "Advanced analytics",
        "Trading reports",
        "Performance exports",
    ]
}
