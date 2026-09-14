import SwiftUI

/// Dashboard / Settings withdrawal history — observes ``WithdrawalsHistoryStore`` directly.
struct PayoutsScreenView: View {
    @Bindable private var withdrawalsHistory = WithdrawalsHistoryStore.shared
    @State private var accountsViewModel: ManageAccountsViewModel
    @State private var isRevalidatingCycles = false

    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment?

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator? = nil) {
        self.data = data
        _ = navigationCoordinator
        _accountsViewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    init(viewModel: ManageAccountsViewModel) {
        self.data = nil
        _accountsViewModel = State(initialValue: viewModel)
    }

    private var historyItems: [PayoutHistoryItem] {
        PayoutHistorySupport.buildHistory(
            accounts: accountsViewModel.accounts,
            entriesByAccount: withdrawalsHistory.ledgerByAccount,
            cyclesByAccount: withdrawalsHistory.cyclesByAccount
        )
    }

    private var accountsByID: [TradingAccountID: TradingAccount] {
        Dictionary(uniqueKeysWithValues: accountsViewModel.accounts.map { ($0.id, $0) })
    }

    private var liveWithdrawals: [PayoutHistoryItem] {
        PayoutHistorySupport.liveWithdrawals(from: historyItems, accountsByID: accountsByID)
    }

    private var propPayouts: [PayoutHistoryItem] {
        PayoutHistorySupport.propPayouts(from: historyItems, accountsByID: accountsByID)
    }

    private var totalWithdrawals: Decimal {
        PayoutHistorySupport.summary(for: historyItems).total
    }

    private var equityCurvePoints: [PayoutEquityCurvePoint] {
        PayoutEquityCurveSupport.buildPoints(from: historyItems)
    }

    var body: some View {
        Group {
            if let error = accountsViewModel.errorMessage,
               accountsViewModel.accounts.isEmpty,
               !accountsViewModel.isLoading
            {
                ExperienceErrorState(
                    title: "Couldn't load withdrawals",
                    message: error,
                    onRetry: { Task { await hydrateWithdrawalsScreen() } }
                )
            } else {
                content
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Withdrawals")
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            WithdrawalsTrace.log("viewAppeared")
            WithdrawalsTrace.storeIdentity("withdrawalsScreen")
        }
        .onDisappear {
            WithdrawalsHydrationPriorityGate.setScreenActive(false)
        }
        .refreshable {
            WithdrawalsHydrationPriorityGate.setScreenActive(true)
            defer { WithdrawalsHydrationPriorityGate.setScreenActive(false) }
            await hydrateWithdrawalsScreen()
        }
        .task {
            WithdrawalsTrace.log("taskStarted")
            WithdrawalsHydrationPriorityGate.setScreenActive(true)
            defer { WithdrawalsHydrationPriorityGate.setScreenActive(false) }
            await hydrateWithdrawalsScreen()
        }
        .accessibilityIdentifier("withdrawals.home")
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                totalSection
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.sm)

                PayoutEquityCurveView(
                    points: equityCurvePoints,
                    totalWithdrawals: totalWithdrawals,
                    hasWithdrawals: !historyItems.isEmpty
                )
                .padding(.horizontal, ExperienceSpacing.md)

                if showInitialLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, ExperienceSpacing.xl)
                } else if historyItems.isEmpty {
                    ExperienceEmptyState(
                        icon: .payouts,
                        title: "No withdrawals yet",
                        message: "Withdrawals you record from Create will appear here."
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                } else {
                    if !liveWithdrawals.isEmpty {
                        historySection(title: "Live Withdrawals", items: liveWithdrawals)
                    }
                    if !propPayouts.isEmpty {
                        historySection(title: "Prop Payouts", items: propPayouts)
                    }
                }
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private var showInitialLoading: Bool {
        historyItems.isEmpty
            && withdrawalsHistory.isEmpty
            && (accountsViewModel.isLoading || accountsViewModel.isLoadingPayouts || isRevalidatingCycles)
    }

    private var totalSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Total Withdrawals")
                .experienceStyle(.subheadline, color: colors.secondaryText)
            Text(ProfileDisplay.formatMoney(totalWithdrawals))
                .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .accessibilityIdentifier("withdrawals.total")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func historySection(title: String, items: [PayoutHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)

            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    PayoutHistoryRowView(
                        item: item,
                        account: accountsByID[item.accountID]
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.xxs)
                    .background(colors.backgroundPrimary)
                    if item.id != items.last?.id {
                        Divider()
                            .padding(.leading, ExperienceSpacing.md)
                    }
                }
            }
            .background(colors.fillSecondary.opacity(0.25), in: RoundedRectangle(
                cornerRadius: ExperienceRadius.md,
                style: .continuous
            ))
            .padding(.horizontal, ExperienceSpacing.md)
        }
    }

    private func hydrateProfileAndCaches() async {
        guard let data else {
            WithdrawalsTrace.log("earlyReturn", detail: "noDataEnvironment")
            return
        }
        guard let userID = await data.session.currentUserID else {
            WithdrawalsTrace.log("earlyReturn", detail: "noSessionUser")
            return
        }
        let profileID = ProfileID(userID.rawValue)
        WithdrawalsTrace.log("taskStarted", detail: "userID=\(profileID.rawValue)")
        withdrawalsHistory.bindProfile(profileID)
        withdrawalsHistory.hydrateFromSessionCaches(profileID: profileID)
        WithdrawalsTrace.log(
            "sessionLedgerHydrated",
            detail: "entries=\(withdrawalsHistory.ledgerEntryCount())"
        )
    }

    private func hydrateWithdrawalsScreen() async {
        await hydrateProfileAndCaches()
        await accountsViewModel.ensureAccountsReadyForWithdrawals()

        guard !accountsViewModel.accounts.isEmpty else {
            WithdrawalsTrace.log("earlyReturn", detail: "accountsEmptyAfterEnsure")
            logPublishedSummary(phase: "accountsEmpty")
            return
        }

        if let data, let userID = await data.session.currentUserID {
            let profileID = ProfileID(userID.rawValue)
            let fundedIDs = accountsViewModel.accounts
                .filter { PropFirmPayoutPolicy.supportsRecordPayout(for: $0) }
                .map(\.id)
            withdrawalsHistory.hydrateCyclesFromSessionStore(
                profileID: profileID,
                accountIDs: fundedIDs
            )
            WithdrawalsTrace.log(
                "cyclesHydrated",
                detail: "cachedCompleted=\(withdrawalsHistory.completedPropCycleCount())"
            )
        }

        logPublishedSummary(phase: "beforeNetwork")

        await accountsViewModel.loadAllPayoutEntries()
        await revalidateCyclesFromServer()

        logPublishedSummary(phase: "afterNetwork")
    }

    private func revalidateCyclesFromServer() async {
        guard let data else { return }
        guard let userID = await data.session.currentUserID else { return }
        let profileID = ProfileID(userID.rawValue)
        let accountIDs = accountsViewModel.accounts
            .filter { PropFirmPayoutPolicy.supportsRecordPayout(for: $0) }
            .map(\.id)
        guard !accountIDs.isEmpty else { return }

        isRevalidatingCycles = true
        defer { isRevalidatingCycles = false }
        WithdrawalsTrace.log("cyclesFetchStarted", detail: "accounts=\(accountIDs.count)")
        do {
            let cycles = try await data.trades.payoutCycleHistory(for: accountIDs)
            var grouped: [TradingAccountID: [AccountPayoutCycle]] = [:]
            for accountID in accountIDs {
                grouped[accountID] = []
            }
            for cycle in cycles {
                grouped[cycle.accountID, default: []].append(cycle)
            }
            withdrawalsHistory.applyCyclesSnapshot(grouped, profileID: profileID)
            WithdrawalsTrace.log(
                "cyclesFetchCompleted",
                detail: "cycles=\(cycles.count) completed=\(withdrawalsHistory.completedPropCycleCount())"
            )
        } catch {
            WithdrawalsTrace.log("cyclesFetchFailed", detail: error.localizedDescription)
        }
    }

    private func logPublishedSummary(phase: String) {
        WithdrawalsTrace.log(
            "published",
            detail: "\(phase) live=\(liveWithdrawals.count) prop=\(propPayouts.count) total=\(totalWithdrawals) ledgerRows=\(withdrawalsHistory.ledgerEntryCount())"
        )
    }
}
