import SwiftUI

struct SettingsSubscriptionView: View {
    @State private var viewModel: SettingsSubscriptionViewModel

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

            planSection

            if viewModel.showsProMembership {
                activeMembershipSection
            }

            if viewModel.showsFreePlanDetails, let status = viewModel.status {
                freeLimitsSection(status: status)
                traxProHighlightsSection
                if viewModel.showsApplePurchaseSection {
                    productsSection
                    purchaseSection
                    legalSection
                }
            }

            if viewModel.showsRestorePurchases {
                restoreSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Plan")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .accessibilityIdentifier("settings.subscription")
    }

    private var planSection: some View {
        Section {
            SettingsInfoRow(title: "Plan", value: viewModel.planTitle)
            if let billingDetail = viewModel.billingDetail {
                SettingsInfoRow(title: "Membership", value: billingDetail)
            }
            if let renewalDetail = viewModel.renewalDetail {
                SettingsInfoRow(title: "Renewal", value: renewalDetail)
            }
        } footer: {
            Text(viewModel.membershipSummaryFooter)
        }
    }

    private var activeMembershipSection: some View {
        Section {
            if viewModel.showsManageSubscription {
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
        } header: {
            Text("TraxPro")
        }
    }

    private func freeLimitsSection(status: BillingStatus) -> some View {
        Section {
            if let trades = status.dailyTradeLimit {
                SettingsInfoRow(title: "Daily trades", value: "\(trades)")
            }
            if let posts = status.dailyPostLimit {
                SettingsInfoRow(title: "Daily posts", value: "\(posts)")
            }
            SettingsInfoRow(title: "Daily clips", value: "\(FreeTierPolicy.dailyReelLimit)")
            if let messages = status.dailyMessageLimit {
                SettingsInfoRow(title: "Daily messages", value: "\(messages)")
            }
            if let accounts = status.maxTradeEntryAccounts {
                SettingsInfoRow(title: "Active accounts", value: "\(accounts)")
            }
        } header: {
            Text("Included on Free")
        } footer: {
            Text("These limits apply to your current Free membership.")
        }
    }

    private var traxProHighlightsSection: some View {
        Section {
            SettingsIntroBlock(
                title: "TraxPro",
                message: "Unlock Trade AI, higher daily limits, more trading accounts, and advanced analytics."
            )
            ForEach(viewModel.traxProFeatureHighlights, id: \.self) { feature in
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 20, alignment: .center)
                        .padding(.top, 2)
                    Text(feature)
                        .experienceStyle(.body, color: colors.primaryText)
                }
                .padding(.vertical, ExperienceSpacing.xxs)
            }
        } header: {
            Text("TraxPro Includes")
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
                .padding(.vertical, ExperienceSpacing.xs)
            case .failed:
                SettingsInlineError(message: "Couldn't load App Store plans right now.") {
                    viewModel.retryLoadProducts()
                }
            case .loaded(let products):
                ForEach(products) { product in
                    Button {
                        viewModel.selectProduct(product.id)
                    } label: {
                        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                                Text(product.displayName)
                                    .experienceStyle(.body, color: colors.primaryText)
                                Text("\(product.displayPrice) / \(product.subscriptionPeriodLabel)")
                                    .experienceStyle(.footnote, color: colors.secondaryText)
                            }
                            Spacer(minLength: ExperienceSpacing.sm)
                            Image(systemName: viewModel.selectedProduct?.id == product.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    viewModel.selectedProduct?.id == product.id ? colors.accent : colors.tertiaryText
                                )
                        }
                        .padding(.vertical, ExperienceSpacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.subscription.product.\(product.id)")
                }
            }
        } header: {
            Text("Choose a Plan")
        } footer: {
            Text("Prices are shown by the App Store for your region.")
        }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if case .loaded = viewModel.productsState {
            Section {
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
                    .padding(.vertical, ExperienceSpacing.xs)
                }
                .disabled(viewModel.isPrimaryActionDisabled)
                .accessibilityIdentifier("settings.subscription.subscribe")
            } footer: {
                Text(SubscriptionPresentationPolicy.autoRenewDisclosure(selectedProduct: viewModel.selectedProduct))
            }
        }
    }

    private var legalSection: some View {
        Section {
            legalLink(title: "Terms of Use", url: LegalDocuments.terms)
            legalLink(title: "Privacy Policy", url: LegalDocuments.privacy)
        } header: {
            Text("Legal")
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
        } footer: {
            Text("Restores App Store purchases for the signed-in Apple ID on this device.")
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
}
