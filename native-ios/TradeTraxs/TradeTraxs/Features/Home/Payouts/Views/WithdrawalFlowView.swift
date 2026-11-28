import SwiftUI

/// Create → Withdrawal, Live manual ledger or Funded prop-firm record flow.
struct WithdrawalFlowView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let onDismiss: () -> Void

    @State private var viewModel: ManageAccountsViewModel
    @State private var selectedAccountID: TradingAccountID?
    @State private var draft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
    @State private var recordPayoutAccountID: TradingAccountID?
    @State private var pendingLiveAchievementPrompt: (
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft,
        ledgerEntryID: AccountPayoutEntryID
    )?

    @Bindable private var withdrawalsHistory = WithdrawalsHistoryStore.shared

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        onDismiss: @escaping () -> Void
    ) {
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.onDismiss = onDismiss
        _viewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
    }

    private var withdrawalAccounts: [TradingAccount] {
        viewModel.accounts.filter { PropFirmPayoutPolicy.supportsWithdrawal(for: $0) }
    }

    /// Payout-ready funded accounts first; everyone else keeps list order within each group.
    private var orderedWithdrawalAccounts: [TradingAccount] {
        var ready: [TradingAccount] = []
        var remaining: [TradingAccount] = []
        for account in withdrawalAccounts {
            if isPayoutReadyAccount(account) {
                ready.append(account)
            } else {
                remaining.append(account)
            }
        }
        return ready + remaining
    }

    var body: some View {
        Group {
            if let pending = pendingLiveAchievementPrompt {
                liveAchievementPrompt(
                    accountID: pending.accountID,
                    draft: pending.draft,
                    ledgerEntryID: pending.ledgerEntryID
                )
            } else if let accountID = selectedAccountID {
                liveLedgerForm(accountID: accountID)
            } else {
                accountPicker
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Withdrawal")
        .toolbar {
            if pendingLiveAchievementPrompt != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            } else if selectedAccountID == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
        .sheet(isPresented: recordPayoutPresented) {
            if let accountID = recordPayoutAccountID {
                RecordPayoutFlowView(
                    accountID: accountID,
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    onWithdrawalFlowComplete: onDismiss
                )
            }
        }
        .task {
            viewModel.loadIfNeeded()
            let deadline = Date().addingTimeInterval(5)
            while viewModel.accounts.isEmpty, Date() < deadline {
                if !viewModel.isLoading { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if let profileID = viewModel.viewerProfileID {
                withdrawalsHistory.bindProfile(profileID)
                withdrawalsHistory.hydrateFromSessionCaches(profileID: profileID)
            }
        }
        .accessibilityIdentifier("withdrawal.flow")
    }

    private var recordPayoutPresented: Binding<Bool> {
        Binding(
            get: { recordPayoutAccountID != nil },
            set: { if !$0 { recordPayoutAccountID = nil } }
        )
    }

    private var accountPicker: some View {
        List {
            if viewModel.isLoading, withdrawalAccounts.isEmpty {
                Section {
                    HStack {
                        ExperienceIndeterminateProgress()
                        Text("Loading accounts…")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                    .experienceDashboardListRow()
                }
            } else if withdrawalAccounts.isEmpty {
                Section {
                    SettingsIntroBlock(
                        title: "No eligible accounts",
                        message: "Add a live or funded prop firm account under Settings → Manage Accounts, or your account's payout rules have not yet been met."
                    )
                    .experienceDashboardListRow()
                }
            } else {
                Section("Account") {
                    ForEach(orderedWithdrawalAccounts) { account in
                        Button {
                            ExperienceHaptics.play(.selection)
                            draft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
                            if PropFirmPayoutPolicy.supportsRecordPayout(for: account) {
                                recordPayoutAccountID = account.id
                            } else {
                                selectedAccountID = account.id
                            }
                        } label: {
                            withdrawalAccountRow(for: account)
                        }
                        .buttonStyle(.experiencePlain)
                        .experienceDashboardListRow()
                        .accessibilityIdentifier("withdrawal.account.\(account.id.rawValue)")
                    }
                }
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: false)
        .listRowSeparatorTint(colors.separator)
        .listSectionSpacing(ExperienceSpacing.xs)
    }

    private func liveLedgerForm(accountID: TradingAccountID) -> some View {
        Form {
            if let account = viewModel.accounts.first(where: { $0.id == accountID }) {
                Section {
                    LabeledContent("Account", value: TradingAccountDisplay.title(for: account, audience: .owner))
                        .experienceDashboardListRow()
                    LabeledContent("Mode", value: TradingAccountDisplay.ownerDropdownModeLabel(account.mode))
                        .experienceDashboardListRow()
                }
            }
            Section {
                SettingsLabeledField(title: "Withdrawal Amount (USD)") {
                    TextField("0", text: $draft.amountDigits.numericInput(.unsignedCurrency))
                        .keyboardType(.decimalPad)
                }
                .experienceDashboardListRow()
                DatePicker("Date", selection: $draft.payoutDate, in: ...Date(), displayedComponents: .date)
                    .experienceDashboardListRow()
                SettingsLabeledField(title: "Notes") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(2...3)
                }
                .experienceDashboardListRow()
            } header: {
                Text("Withdrawal")
            }

            if let error = viewModel.payoutError {
                Section {
                    Text(error)
                        .experienceStyle(.footnote, color: colors.loss)
                        .experienceDashboardListRow()
                }
            }
        }
        .listRowSeparatorTint(colors.separator)
        .listSectionSpacing(ExperienceSpacing.xs)
        .scrollDismissesKeyboard(.interactively)
        .experienceTradeTraxsFormStyle(pageBackground: false)
        .experienceArrowBackToolbarButton {
            selectedAccountID = nil
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        let savedDraft = draft
                        if let entryID = await viewModel.createPayout(accountID: accountID, draft: savedDraft) {
                            selectedAccountID = nil
                            pendingLiveAchievementPrompt = (accountID, savedDraft, entryID)
                        }
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .experienceProtectedFormDismiss()
    }

    private func liveAchievementPrompt(
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft,
        ledgerEntryID: AccountPayoutEntryID
    ) -> some View {
        PostWithdrawalAchievementPrompt(
            onCreateAchievement: {
                guard let account = viewModel.accounts.first(where: { $0.id == accountID }) else {
                    pendingLiveAchievementPrompt = nil
                    onDismiss()
                    return
                }
                let prefill = PropFirmPayoutCycleSupport.liveWithdrawalAchievementPrefill(
                    account: account,
                    draft: draft,
                    withdrawalLink: .ledgerEntry(ledgerEntryID)
                )
                CreateAchievementPrefillStore.shared.stage(prefill)
                pendingLiveAchievementPrompt = nil
                onDismiss()
                navigationCoordinator.openComposeAchievement()
            },
            onNotNow: {
                pendingLiveAchievementPrompt = nil
                onDismiss()
            }
        )
    }

    private func withdrawalAccountRow(for account: TradingAccount) -> some View {
        let payoutReady = isPayoutReadyAccount(account)
        return HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: accountIcon(for: account))
                .font(.body.weight(.medium))
                .foregroundStyle(colors.accent)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(TradingAccountDisplay.title(for: account, audience: .owner))
                    .experienceStyle(.body, color: colors.primaryText)
                Text(accountSubtitle(for: account))
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            Spacer(minLength: ExperienceSpacing.xs)
            if payoutReady {
                Text("Ready For a Payout!")
                    .experienceStyle(.caption, color: colors.profit)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("withdrawal.account.\(account.id.rawValue).payoutReady")
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .contentShape(Rectangle())
    }

    private func isPayoutReadyAccount(_ account: TradingAccount) -> Bool {
        propFirmSnapshot(for: account)?.payoutReady == true
    }

    private func propFirmSnapshot(for account: TradingAccount) -> PropFirmStatusSnapshot? {
        guard PropFirmPayoutPolicy.supportsRecordPayout(for: account) else { return nil }
        let trades: [Trade] = {
            guard let profileID = viewModel.viewerProfileID else { return [] }
            return data.detailCache.tradesOwnedBy(profileID).filter { $0.accountID == account.id }
        }()
        let cycles = withdrawalsHistory.cyclesByAccount[account.id] ?? []
        return PropFirmStatusSnapshot.build(
            account: account,
            trades: trades,
            payoutCycles: cycles
        )
    }

    private func accountSubtitle(for account: TradingAccount) -> String {
        let mode = TradingAccountDisplay.ownerDropdownModeLabel(account.mode)
        if PropFirmPayoutPolicy.supportsRecordPayout(for: account) {
            return "\(mode) · Prop payout"
        }
        return mode
    }

    private func accountIcon(for account: TradingAccount) -> String {
        PropFirmPayoutPolicy.supportsRecordPayout(for: account)
            ? "building.columns"
            : "chart.line.uptrend.xyaxis"
    }
}
