import SwiftUI

/// Owner payout hub — funded prop cycles via Record Payout; legacy manual ledger elsewhere.
struct PayoutsScreenView: View {
    @State private var viewModel: ManageAccountsViewModel
    @State private var payoutSheetContext: PayoutSheetContext?
    @State private var recordPayoutAccountID: TradingAccountID?
    @State private var payoutCyclesByAccount: [TradingAccountID: [AccountPayoutCycle]] = [:]
    @State private var loadingCycleAccounts: Set<TradingAccountID> = []

    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment?
    private let navigationCoordinator: NavigationCoordinator?

    private struct PayoutSheetContext: Identifiable {
        let accountID: TradingAccountID
        let editingEntryID: AccountPayoutEntryID?
        var draft: AccountPayoutEntryDraft

        var id: String {
            accountID.rawValue + (editingEntryID?.rawValue ?? "new")
        }
    }

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    init(viewModel: ManageAccountsViewModel) {
        self.data = nil
        self.navigationCoordinator = nil
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.accounts.isEmpty, !viewModel.isLoading {
                ExperienceErrorState(
                    title: "Couldn't load payouts",
                    message: error,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            } else {
                payoutList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Payouts")
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            await viewModel.refresh()
            await reloadAllPayoutData()
        }
        .task {
            viewModel.loadIfNeeded()
            await loadPayoutsWhenReady()
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            Task { await reloadFundedCycleHistory() }
        }
        .sheet(item: $payoutSheetContext) { context in
            AccountPayoutEditorSheet(
                viewModel: viewModel,
                accountID: context.accountID,
                editingEntryID: context.editingEntryID,
                draft: bindingDraft(for: context),
                isPresented: Binding(
                    get: { payoutSheetContext != nil },
                    set: { if !$0 { payoutSheetContext = nil } }
                )
            )
        }
        .sheet(isPresented: recordPayoutPresented) {
            if let accountID = recordPayoutAccountID,
               let data,
               let navigationCoordinator {
                RecordPayoutFlowView(
                    accountID: accountID,
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            }
        }
        .accessibilityIdentifier("payouts.home")
    }

    private var recordPayoutPresented: Binding<Bool> {
        Binding(
            get: { recordPayoutAccountID != nil },
            set: { if !$0 { recordPayoutAccountID = nil } }
        )
    }

    private var fundedAccounts: [TradingAccount] {
        viewModel.accounts.filter { PropFirmPayoutPolicy.supportsRecordPayout(for: $0) }
    }

    private var manualLedgerAccounts: [TradingAccount] {
        viewModel.accounts.filter { PropFirmPayoutPolicy.supportsManualPayoutLedger(for: $0) }
    }

    private var payoutList: some View {
        List {
            Section {
                introBlock
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if viewModel.isLoading, viewModel.accounts.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading accounts…")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                }
            } else if viewModel.accounts.isEmpty {
                Section {
                    SettingsIntroBlock(
                        title: "No trading accounts yet",
                        message: "Add an account from Manage Accounts to track payouts here."
                    )
                }
            } else {
                if !fundedAccounts.isEmpty {
                    Section {
                        Text("Funded prop-firm accounts use payout cycles. Recording a payout closes the current cycle and starts the next from your post-payout balance.")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    } header: {
                        Text("Record Payout")
                    }

                    ForEach(fundedAccounts) { account in
                        Section {
                            fundedAccountContent(account)
                        } header: {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                                Text(TradingAccountDisplay.title(for: account, audience: .owner))
                                Text(viewModel.subtitle(for: account))
                                    .font(.caption)
                                    .foregroundStyle(colors.secondaryText)
                            }
                        }
                        .task(id: account.id.rawValue) {
                            await loadPayoutCycles(for: account.id)
                        }
                    }
                }

                if !manualLedgerAccounts.isEmpty {
                    Section {
                        Text("Private ledger entries for live and other supported accounts. Share payouts publicly by posting payout achievements.")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    } header: {
                        Text("Manual Payouts")
                    }

                    ForEach(manualLedgerAccounts) { account in
                        Section {
                            AccountPayoutListContent(
                                viewModel: viewModel,
                                accountID: account.id,
                                onAdd: { presentAddPayout(for: account.id) },
                                onEdit: { entry in presentEditPayout(entry, accountID: account.id) }
                            )
                        } header: {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                                Text(TradingAccountDisplay.title(for: account, audience: .owner))
                                Text(viewModel.subtitle(for: account))
                                    .font(.caption)
                                    .foregroundStyle(colors.secondaryText)
                            }
                        }
                        .task(id: account.id.rawValue) {
                            await viewModel.loadPayoutEntries(for: account.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func fundedAccountContent(_ account: TradingAccount) -> some View {
        Button {
            recordPayoutAccountID = account.id
        } label: {
            Label("Record Payout", systemImage: "dollarsign.circle")
        }
        .disabled(navigationCoordinator == nil)
        .accessibilityIdentifier("payouts.recordPayout.\(account.id.rawValue)")

        if loadingCycleAccounts.contains(account.id),
           payoutCyclesByAccount[account.id] == nil {
            HStack {
                ProgressView()
                Text("Loading payout history…")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
        } else {
            FundedPayoutCycleHistoryContent(
                cycles: PropFirmPayoutCycleSupport.selectCompletedPayoutHistory(
                    payoutCyclesByAccount[account.id] ?? []
                )
            )
        }
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Payouts")
                .experienceStyle(.title2, color: colors.primaryText)
            Text("Record funded prop-firm payouts against your payout cycles, or maintain a private manual ledger on supported accounts.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.accent.opacity(0.16),
                            colors.fillSecondary.opacity(0.65),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .accessibilityIdentifier("payouts.intro")
    }

    private func presentAddPayout(for accountID: TradingAccountID) {
        payoutSheetContext = PayoutSheetContext(
            accountID: accountID,
            editingEntryID: nil,
            draft: AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
        )
    }

    private func presentEditPayout(_ entry: AccountPayoutEntry, accountID: TradingAccountID) {
        payoutSheetContext = PayoutSheetContext(
            accountID: accountID,
            editingEntryID: entry.id,
            draft: AccountPayoutEntryDraft(
                amountDigits: NSDecimalNumber(decimal: entry.amount.amount).stringValue,
                payoutDate: entry.payoutDate,
                note: entry.note ?? ""
            )
        )
    }

    private func bindingDraft(for context: PayoutSheetContext) -> Binding<AccountPayoutEntryDraft> {
        Binding(
            get: { payoutSheetContext?.draft ?? context.draft },
            set: { newValue in
                payoutSheetContext?.draft = newValue
            }
        )
    }

    private func loadPayoutsWhenReady() async {
        let deadline = Date().addingTimeInterval(5)
        while viewModel.accounts.isEmpty, Date() < deadline {
            if !viewModel.isLoading { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !viewModel.accounts.isEmpty else { return }
        await reloadAllPayoutData()
    }

    private func reloadAllPayoutData() async {
        await viewModel.loadAllPayoutEntries()
        await reloadFundedCycleHistory()
    }

    private func reloadFundedCycleHistory() async {
        guard let data else { return }
        let accountIDs = fundedAccounts.map(\.id)
        guard !accountIDs.isEmpty else { return }
        loadingCycleAccounts.formUnion(accountIDs)
        defer { loadingCycleAccounts.subtract(accountIDs) }

        let started = CFAbsoluteTimeGetCurrent()
        do {
            let cycles = try await data.trades.payoutCycleHistory(for: accountIDs)
            var grouped: [TradingAccountID: [AccountPayoutCycle]] = [:]
            for accountID in accountIDs {
                grouped[accountID] = []
            }
            for cycle in cycles {
                grouped[cycle.accountID, default: []].append(cycle)
            }
            payoutCyclesByAccount.merge(grouped) { _, new in new }
            PayoutBatchDiagnostics.logCycles(
                accounts: accountIDs.count,
                requests: 1,
                cycles: cycles.count,
                dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            )
        } catch {
            for accountID in accountIDs {
                payoutCyclesByAccount[accountID] = []
            }
        }
    }

    private func loadPayoutCycles(for accountID: TradingAccountID, trades: any TradeRepository) async {
        loadingCycleAccounts.insert(accountID)
        defer { loadingCycleAccounts.remove(accountID) }
        do {
            let cycles = try await trades.payoutCycleHistory(for: accountID)
            payoutCyclesByAccount[accountID] = cycles
        } catch {
            payoutCyclesByAccount[accountID] = []
        }
    }

    private func loadPayoutCycles(for accountID: TradingAccountID) async {
        guard let data else { return }
        await loadPayoutCycles(for: accountID, trades: data.trades)
    }
}
