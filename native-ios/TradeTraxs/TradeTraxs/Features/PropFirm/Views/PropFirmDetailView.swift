import SwiftUI

/// Dedicated Prop Firm account detail, rules, risk, targets, payouts.
struct PropFirmDetailView: View {
    @State private var viewModel: PropFirmDetailViewModel

    private let recordPayoutData: DataEnvironment?
    private let recordPayoutCoordinator: NavigationCoordinator?

    @Environment(\.themeColors) private var colors

    init(
        accountID: TradingAccountID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.recordPayoutData = data
        self.recordPayoutCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: PropFirmDetailViewModel(
                accountID: accountID,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                rpc: data.rpc,
                realtimeHub: data.realtimeHub,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    /// Tests.
    init(viewModel: PropFirmDetailViewModel) {
        self.recordPayoutData = nil
        self.recordPayoutCoordinator = nil
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                let contentPlan = PropFirmDetailContentPlan(snapshot: snapshot)
                ScrollView {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                        PropFirmDetailSummaryView(
                            snapshot: snapshot,
                            glanceLines: contentPlan.glanceLines(),
                            fundedPayoutActionTitle: snapshot.isFunded
                                ? PropFirmDetailViewModel.payoutEntryTitle(
                                    hasRecordedPayouts: !snapshot.completedPayoutHistory.isEmpty
                                )
                                : nil,
                            onFundedPayoutAction: snapshot.isFunded
                                ? { viewModel.openPayoutsPage() }
                                : nil
                        )

                        let metricChips = contentPlan.dashboardMetricChips()
                        if !metricChips.isEmpty {
                            DashboardMetricStrip(chips: metricChips)
                                .accessibilityIdentifier("propFirm.metrics")
                        }

                        if contentPlan.showsProgressSection {
                            PropFirmDetailProgressPanel(
                                snapshot: snapshot,
                                contentPlan: contentPlan
                            )
                        }

                        if contentPlan.showsDrawdownSection {
                            PropFirmDetailDrawdownPanel(
                                snapshot: snapshot,
                                contentPlan: contentPlan
                            )
                        }

                        PropFirmDetailTradingRulesPanel(
                            snapshot: snapshot,
                            contentPlan: contentPlan
                        )
                    }
                    .padding(.vertical, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.lg)
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "Prop account unavailable",
                    message: viewModel.errorMessage ?? "Select a prop-firm account from the Dashboard."
                )
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                propFirmAccountMenu
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            if case .generic = AccountMutationStore.shared.latestKind {
                viewModel.handleAccountMutation()
            } else {
                Task { await viewModel.refresh() }
            }
        }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("propFirm.detail")
    }

    @ViewBuilder
    private var propFirmAccountMenu: some View {
        if !viewModel.accountsForMenu.isEmpty, recordPayoutData != nil {
            OwnerAccountFilterDropdown(
                accounts: viewModel.accountsForMenu,
                selectedFilter: .account(viewModel.accountID),
                copyGroups: [],
                isLoadingCopyGroups: false,
                onSelectFilter: { filter in
                    if case .account(let id) = filter {
                        Task { await viewModel.selectAccount(id) }
                    }
                },
                onManageAccounts: { viewModel.openManageAccounts() },
                onManageCopyGroups: {},
                onRequestCopyGroups: {},
                accessibilityIdentifier: "propFirm.account",
                includesCopyTradingMenu: false,
                boundary: .dashboard,
                profileID: viewModel.ownerProfileID,
                detailCache: recordPayoutData?.detailCache
            ) {
                HStack(spacing: 4) {
                    Text(viewModel.selectedAccountMenuTitle)
                        .experienceStyle(.footnote, color: colors.primaryText)
                        .lineLimit(1)
                    ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
                }
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, 6)
                .background(colors.fillSecondary, in: Capsule())
            }
            .accessibilityLabel("Prop account")
            .accessibilityValue(viewModel.selectedAccountMenuTitle)
        }
    }
}