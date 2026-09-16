import SwiftUI

/// Dedicated Prop Firm account detail — rules, risk, targets, payouts.
struct PropFirmDetailView: View {
    let accountID: TradingAccountID
    @State private var viewModel: PropFirmDetailViewModel
    @State private var showsRecordPayout = false

    private let recordPayoutData: DataEnvironment?
    private let recordPayoutCoordinator: NavigationCoordinator?

    init(
        accountID: TradingAccountID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.accountID = accountID
        self.recordPayoutData = data
        self.recordPayoutCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: PropFirmDetailViewModel(
                accountID: accountID,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                rpc: data.rpc,
                realtimeHub: data.realtimeHub
            )
        )
    }

    /// Tests.
    init(viewModel: PropFirmDetailViewModel) {
        self.accountID = viewModel.accountID
        self.recordPayoutData = nil
        self.recordPayoutCoordinator = nil
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                let contentPlan = PropFirmDetailContentPlan(snapshot: snapshot)
                ScrollView {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                        PropFirmDetailHeroView(snapshot: snapshot, contentPlan: contentPlan)

                        let glance = contentPlan.glanceLines()
                        if !glance.isEmpty {
                            PropFirmAtAGlanceView(lines: glance)
                        }

                        if contentPlan.showsAccountSizeSection {
                            accountSizeChip(snapshot)
                        }

                        PropFirmEvaluationMetricsView(snapshot: snapshot)

                        if contentPlan.showsDrawdownSection {
                            PropFirmDrawdownVisualView(snapshot: snapshot)
                        }

                        PropFirmConsistencyVisualView(snapshot: snapshot)

                        PropFirmTradingRulesView(snapshot: snapshot, contentPlan: contentPlan)

                        if snapshot.isFunded {
                            PropFirmFundedLiveView(snapshot: snapshot)
                        }

                        PropFirmJourneyStepperView(
                            title: snapshot.isFunded ? "Payout path" : "Evaluation path",
                            steps: PropFirmDetailPresentation.journeySteps(for: snapshot)
                        )

                        PropFirmDetailPayoutsView(
                            snapshot: snapshot,
                            contentPlan: contentPlan,
                            onRecordPayout: { showsRecordPayout = true },
                            recordPayoutEnabled: recordPayoutData != nil
                        )

                        let expandable = contentPlan.expandableRules()
                        if !expandable.isEmpty {
                            PropFirmExpandableRulesView(rules: expandable)
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.xl)
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
        .experienceNavigationTitle(viewModel.snapshot?.accountName ?? "Prop Firm")
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $showsRecordPayout) {
            if let data = recordPayoutData, let navigationCoordinator = recordPayoutCoordinator {
                RecordPayoutFlowView(
                    accountID: accountID,
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            }
        }
        .accessibilityIdentifier("propFirm.detail")
    }

    @ViewBuilder
    private func accountSizeChip(_ snapshot: PropFirmStatusSnapshot) -> some View {
        if snapshot.configuredAccountSize > 0 {
            PropFirmDetailSection(title: "Account size") {
                HStack(spacing: ExperienceSpacing.sm) {
                    ExperienceChip(
                        title: DashboardViewModel.money(snapshot.configuredAccountSize),
                        isSelected: true,
                        action: nil
                    )
                    ExperienceTag(title: snapshot.phaseLabel, tone: .info)
                }
            }
        }
    }
}
