import SwiftUI

/// Create → Withdrawal — Live manual ledger or Funded prop-firm record flow.
struct WithdrawalFlowView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let onDismiss: () -> Void

    @State private var viewModel: ManageAccountsViewModel
    @State private var selectedAccountID: TradingAccountID?
    @State private var draft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
    @State private var didRecord = false
    @State private var recordPayoutAccountID: TradingAccountID?

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

    var body: some View {
        Group {
            if didRecord {
                successContent
            } else if let accountID = selectedAccountID {
                liveLedgerForm(accountID: accountID)
            } else {
                accountPicker
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Withdrawal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(didRecord ? "Done" : "Close", action: onDismiss)
            }
        }
        .sheet(isPresented: recordPayoutPresented) {
            if let accountID = recordPayoutAccountID {
                RecordPayoutFlowView(
                    accountID: accountID,
                    data: data,
                    navigationCoordinator: navigationCoordinator
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
            Section {
                Text(
                    "Record money taken out of a Live account or received as a prop-firm payout. Entries appear in Payouts history."
                )
                .experienceStyle(.footnote, color: colors.secondaryText)
            }

            if viewModel.isLoading, withdrawalAccounts.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading accounts…")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                }
            } else if withdrawalAccounts.isEmpty {
                Section {
                    SettingsIntroBlock(
                        title: "No eligible accounts",
                        message: "Add a Live or Funded prop-firm account under Settings → Manage Accounts."
                    )
                }
            } else {
                Section("Account") {
                    ForEach(withdrawalAccounts) { account in
                        Button {
                            ExperienceHaptics.play(.selection)
                            draft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
                            if PropFirmPayoutPolicy.supportsRecordPayout(for: account) {
                                recordPayoutAccountID = account.id
                            } else {
                                selectedAccountID = account.id
                            }
                        } label: {
                            SettingsNavigationRow(
                                title: TradingAccountDisplay.title(for: account, audience: .owner),
                                subtitle: accountSubtitle(for: account),
                                systemImage: accountIcon(for: account)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("withdrawal.account.\(account.id.rawValue)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func liveLedgerForm(accountID: TradingAccountID) -> some View {
        Form {
            if let account = viewModel.accounts.first(where: { $0.id == accountID }) {
                Section {
                    LabeledContent("Account", value: TradingAccountDisplay.title(for: account, audience: .owner))
                    LabeledContent("Mode", value: TradingAccountDisplay.ownerDropdownModeLabel(account.mode))
                }
            }
            Section {
                SettingsLabeledField(title: "Withdrawal amount", helper: "USD") {
                    TextField("0", text: $draft.amountDigits)
                        .keyboardType(.decimalPad)
                }
                DatePicker("Date", selection: $draft.payoutDate, in: ...Date(), displayedComponents: .date)
                SettingsLabeledField(title: "Note", helper: "Optional") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(2...3)
                }
            } header: {
                Text("Withdrawal")
            } footer: {
                Text("Saved to your payout history.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }

            if let error = viewModel.payoutError {
                Section {
                    Text(error)
                        .experienceStyle(.footnote, color: colors.loss)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    selectedAccountID = nil
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        let ok = await viewModel.createPayout(accountID: accountID, draft: draft)
                        if ok {
                            didRecord = true
                            selectedAccountID = nil
                        }
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .experienceProtectedFormDismiss()
    }

    private var successContent: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: 0)
            ExperienceIcon(icon: .checkmark, size: .xl, color: colors.accent)
            Text("Withdrawal recorded")
                .experienceStyle(.title3, color: colors.primaryText)
            Text("Your withdrawal history was updated. Open Withdrawals on the Dashboard or Settings to review.")
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.lg)
            Spacer(minLength: 0)
            ExperienceButton(title: "Done", kind: .primary, action: onDismiss)
                .padding(.horizontal, ExperienceSpacing.lg)
                .padding(.bottom, ExperienceSpacing.lg)
        }
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
