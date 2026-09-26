import SwiftUI

/// Add / Edit Account — web `CreateAccountModal` fields, native form.
struct ManageAccountEditorView: View {
    enum Mode {
        case create
        case edit(TradingAccount)
    }

    @Bindable var viewModel: ManageAccountsViewModel
    let mode: Mode
    @State private var draft: TradingAccountDraft
    @State private var showInAccountDropdowns = true
    @State private var customPublicStatus = ""
    @State private var payoutDraft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
    @State private var editingPayoutID: AccountPayoutEntryID?
    @State private var showsPayoutSheet = false
    @State private var showsRecordPayout = false
    @State private var propFirmFieldText: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment?
    private let navigationCoordinator: NavigationCoordinator?
    private let onCreateSubmit: ((TradingAccountDraft) async -> Bool)?

    init(
        viewModel: ManageAccountsViewModel,
        mode: Mode,
        draft: TradingAccountDraft,
        data: DataEnvironment? = nil,
        navigationCoordinator: NavigationCoordinator? = nil,
        onCreateSubmit: ((TradingAccountDraft) async -> Bool)? = nil
    ) {
        self.viewModel = viewModel
        self.mode = mode
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.onCreateSubmit = onCreateSubmit
        _draft = State(initialValue: draft)
        if case .edit(let account) = mode {
            _showInAccountDropdowns = State(initialValue: account.showInAccountDropdowns)
            _customPublicStatus = State(initialValue: account.customPublicStatus ?? "")
        }
    }

    private var title: String {
        switch mode {
        case .create: return "Add Account"
        case .edit: return "Edit Account"
        }
    }

    private var saveAccountID: TradingAccountID? {
        if case .edit(let account) = mode { return account.id }
        return nil
    }

    var body: some View {
        Form {
            if case .edit = mode {
                Section {
                    Toggle("Display in Account Dropdowns", isOn: $showInAccountDropdowns)
                        .accessibilityIdentifier("manageAccounts.showInDropdowns")
                } footer: {
                    Text("Hide this account from account selectors without deleting its data.")
                }
            }

            Section {
                Picker("Type", selection: $draft.category) {
                    Text("Personal").tag(TradingAccountCategory.personal)
                    Text("Broker").tag(TradingAccountCategory.broker)
                    Text("Prop Firm").tag(TradingAccountCategory.propFirm)
                    Text("Backtest").tag(TradingAccountCategory.backtest)
                }
                .onChange(of: draft.category) { _, category in
                    draft.mode = ManageAccountsViewModel.defaultMode(for: category)
                    if category != .propFirm {
                        draft.propFirmRules = nil
                    } else if draft.propFirmRules == nil {
                        draft.propFirmRules = PropFirmAccountRules()
                    }
                }

                SettingsLabeledField(title: "Account Name") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("manageAccounts.name")
                }

                SettingsLabeledField(title: "Account Value", helper: "Starting or current account size") {
                    TextField("0", text: $draft.sizeDigits.numericInput(.accountSize))
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("manageAccounts.size")
                }

                SettingsLabeledField(title: "Account ID", helper: "Optional broker or firm account number") {
                    TextField("Optional", text: $draft.accountNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if draft.category != .backtest {
                    Picker("Mode", selection: $draft.mode) {
                        ForEach(ManageAccountsViewModel.modes(for: draft.category), id: \.self) { mode in
                            Text(ManageAccountsViewModel.modeLabel(mode, category: draft.category))
                                .tag(mode)
                        }
                    }
                }

                SettingsLabeledField(title: "Note", helper: "Optional reminder for yourself") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                }
            } header: {
                Text("Account")
            } footer: {
                Text("These details help you organize trades across accounts.")
            }

            if draft.category == .propFirm {
                Section {
                    SettingsLabeledField(title: "Max Drawdown", helper: "Dollars") {
                        TextField("0", text: bindingDecimal(\.maxDrawdown))
                            .keyboardType(.decimalPad)
                    }
                    Picker("Drawdown Type", selection: bindingDrawdownType()) {
                        Text("Unspecified").tag(Optional<PropFirmDrawdownType>.none)
                        ForEach(PropFirmDrawdownType.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(Optional(kind))
                        }
                    }
                    SettingsLabeledField(title: "Daily Drawdown", helper: "Dollars") {
                        TextField("0", text: bindingDecimal(\.dailyDrawdown))
                            .keyboardType(.decimalPad)
                    }
                    SettingsLabeledField(title: "Profit Target", helper: "Dollars") {
                        TextField("0", text: bindingDecimal(\.profitTarget))
                            .keyboardType(.decimalPad)
                    }
                    SettingsLabeledField(title: "Consistency", helper: "Percent") {
                        TextField("0", text: bindingDecimal(\.consistencyPercent))
                            .keyboardType(.decimalPad)
                    }
                    SettingsLabeledField(title: "Winning Days Required") {
                        TextField("0", text: bindingInt(\.winningDaysRequired))
                            .keyboardType(.numberPad)
                    }
                    SettingsLabeledField(title: "Winning Day Threshold", helper: "Dollars") {
                        TextField("0", text: bindingDecimal(\.winningDayThreshold))
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Prop Firm Rules")
                } footer: {
                    Text("Optional limits from your prop firm challenge or funded account.")
                }
            }

            if case .edit(let account) = mode {
                Section {
                    SettingsLabeledField(
                        title: "Public Status",
                        helper: "Optional label on your profile (e.g. Passed, Funded, Blown)"
                    ) {
                        TextField("Optional", text: $customPublicStatus)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("manageAccounts.publicStatus")
                    }
                } header: {
                    Text("Profile")
                }

                if PropFirmPayoutPolicy.supportsRecordPayout(for: account) {
                    Section {
                        Button {
                            showsRecordPayout = true
                        } label: {
                            Label("Record Payout", systemImage: "dollarsign.circle")
                        }
                        .disabled(data == nil || navigationCoordinator == nil)
                        .accessibilityIdentifier("manageAccounts.recordPayout")
                    } header: {
                        Text("Payout Cycle")
                    } footer: {
                        Text("Closes the current payout cycle and starts the next from your post-payout balance. Share publicly afterward with a payout Achievement.")
                    }
                }

                if PropFirmPayoutPolicy.supportsManualPayoutLedger(for: account) {
                    Section {
                        AccountPayoutListContent(
                            viewModel: viewModel,
                            accountID: account.id,
                            onAdd: {
                                editingPayoutID = nil
                                payoutDraft = AccountPayoutEntryDraft(amountDigits: "", payoutDate: .now, note: "")
                                showsPayoutSheet = true
                            },
                            onEdit: { entry in
                                editingPayoutID = entry.id
                                payoutDraft = AccountPayoutEntryDraft(
                                    amountDigits: NumericInputFieldSupport.seedEditingText(
                                        from: entry.amount.amount,
                                        style: .unsignedCurrency
                                    ),
                                    payoutDate: entry.payoutDate,
                                    note: entry.note ?? ""
                                )
                                showsPayoutSheet = true
                            }
                        )
                    } header: {
                        Text("Manual Payouts")
                    } footer: {
                        Text("Private to you. Share payouts publicly by posting payout achievements.")
                    }
                } else if !PropFirmPayoutPolicy.supportsRecordPayout(for: account) {
                    Section {
                        Text("Payout recording is not available for evaluation, simulated, or backtest accounts.")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    } header: {
                        Text("Payouts")
                    }
                }
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("manageAccounts.formError")
                }
            }
        }
        .experienceDashboardGroupedRows()
        .experienceNavigationTitle(title)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(mode.isCreate ? "Add" : "Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(viewModel.isSaving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("manageAccounts.save")
            }
        }
        .disabled(viewModel.isSaving)
        .accessibilityIdentifier("manageAccounts.editor")
        .experienceProtectedFormDismiss()
        .sheet(isPresented: $showsPayoutSheet) {
            if let accountID = saveAccountID {
                AccountPayoutEditorSheet(
                    viewModel: viewModel,
                    accountID: accountID,
                    editingEntryID: editingPayoutID,
                    draft: $payoutDraft,
                    isPresented: $showsPayoutSheet
                )
            }
        }
        .sheet(isPresented: $showsRecordPayout) {
            if let accountID = saveAccountID,
               let data,
               let navigationCoordinator {
                RecordPayoutFlowView(
                    accountID: accountID,
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            }
        }
        .task(id: editAccountID?.rawValue) {
            guard let accountID = editAccountID else { return }
            let account = viewModel.accounts.first(where: { $0.id == accountID })
                ?? editModeAccount
            guard let account, PropFirmPayoutPolicy.supportsManualPayoutLedger(for: account) else { return }
            await viewModel.loadPayoutEntries(for: accountID)
        }
        .onChange(of: viewModel.accounts) { _, _ in
            syncInsightsFromViewModel()
        }
    }

    private func syncInsightsFromViewModel() {
        guard case .edit(let account) = mode,
              let latest = viewModel.accounts.first(where: { $0.id == account.id })
        else { return }
        showInAccountDropdowns = latest.showInAccountDropdowns
        customPublicStatus = latest.customPublicStatus ?? ""
    }

    private var editAccountID: TradingAccountID? {
        if case .edit(let account) = mode { return account.id }
        return nil
    }

    private var editModeAccount: TradingAccount? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    private func save() async {
        var ok: Bool
        switch mode {
        case .create:
            if let onCreateSubmit {
                ok = await onCreateSubmit(draft)
            } else {
                ok = await viewModel.create(draft)
            }
        case .edit(let account):
            ok = await viewModel.update(id: account.id, draft: draft)
            if ok {
                ok = await viewModel.updateInsightsSettings(
                    accountID: account.id,
                    showInAccountDropdowns: showInAccountDropdowns,
                    customPublicStatus: customPublicStatus
                )
            }
        }
        if ok { dismiss() }
    }

    private func bindingDecimal(_ keyPath: WritableKeyPath<PropFirmAccountRules, Decimal?>) -> Binding<String> {
        let cacheKey = String(describing: keyPath)
        return Binding(
            get: {
                if let cached = propFirmFieldText[cacheKey] { return cached }
                guard let rules = draft.propFirmRules, let value = rules[keyPath: keyPath] else { return "" }
                return NumericInputFieldSupport.seedEditingText(from: value, style: .propFirmAmount)
            },
            set: { raw in
                let formatted = NumericInputFieldSupport.formatWhileEditing(raw, style: .propFirmAmount)
                propFirmFieldText[cacheKey] = formatted
                var rules = draft.propFirmRules ?? PropFirmAccountRules()
                rules[keyPath: keyPath] = NumericInputFieldSupport.parse(formatted, style: .propFirmAmount)
                draft.propFirmRules = rules
            }
        )
    }

    private func bindingInt(_ keyPath: WritableKeyPath<PropFirmAccountRules, Int?>) -> Binding<String> {
        let cacheKey = String(describing: keyPath)
        return Binding(
            get: {
                if let cached = propFirmFieldText[cacheKey] { return cached }
                guard let rules = draft.propFirmRules, let value = rules[keyPath: keyPath] else { return "" }
                return NumericInputFieldSupport.seedEditingText(from: value, style: .winningDays)
            },
            set: { raw in
                let formatted = NumericInputFieldSupport.formatWhileEditing(raw, style: .winningDays)
                propFirmFieldText[cacheKey] = formatted
                var rules = draft.propFirmRules ?? PropFirmAccountRules()
                rules[keyPath: keyPath] = NumericInputFieldSupport.parseInt(formatted, style: .winningDays)
                draft.propFirmRules = rules
            }
        )
    }

    private func bindingDrawdownType() -> Binding<PropFirmDrawdownType?> {
        Binding(
            get: { draft.propFirmRules?.drawdownType },
            set: { newValue in
                var rules = draft.propFirmRules ?? PropFirmAccountRules()
                rules.drawdownType = newValue
                draft.propFirmRules = rules
            }
        )
    }
}

private extension ManageAccountEditorView.Mode {
    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }
}
