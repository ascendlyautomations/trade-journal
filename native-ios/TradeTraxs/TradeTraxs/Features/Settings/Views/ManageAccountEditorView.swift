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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    init(viewModel: ManageAccountsViewModel, mode: Mode, draft: TradingAccountDraft) {
        self.viewModel = viewModel
        self.mode = mode
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
                    TextField("0", text: $draft.sizeDigits)
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
                    Toggle("Display in Account Dropdowns", isOn: $showInAccountDropdowns)
                        .accessibilityIdentifier("manageAccounts.showInDropdowns")

                    SettingsLabeledField(
                        title: "Public Status",
                        helper: "Optional label on your profile (e.g. Passed, Funded, Blown)"
                    ) {
                        TextField("Optional", text: $customPublicStatus)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("manageAccounts.publicStatus")
                    }
                } header: {
                    Text("Profile & Pickers")
                } footer: {
                    Text("Hidden accounts stay in Manage Accounts and your trade history. They only disappear from Add Trade and account filters.")
                }

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
                                amountDigits: NSDecimalNumber(decimal: entry.amount.amount).stringValue,
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
        .experienceNavigationTitle(title)
        .scrollDismissesKeyboard(.interactively)
        .experienceKeyboardDoneToolbar()
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
        .task(id: editAccountID?.rawValue) {
            guard let accountID = editAccountID else { return }
            await viewModel.loadPayoutEntries(for: accountID)
        }
    }

    private var editAccountID: TradingAccountID? {
        if case .edit(let account) = mode { return account.id }
        return nil
    }

    private func save() async {
        var ok: Bool
        switch mode {
        case .create:
            ok = await viewModel.create(draft)
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
        Binding(
            get: {
                guard let rules = draft.propFirmRules, let value = rules[keyPath: keyPath] else { return "" }
                return NSDecimalNumber(decimal: value).stringValue
            },
            set: { raw in
                var rules = draft.propFirmRules ?? PropFirmAccountRules()
                let digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                rules[keyPath: keyPath] = digits.isEmpty ? nil : Decimal(string: digits)
                draft.propFirmRules = rules
            }
        )
    }

    private func bindingInt(_ keyPath: WritableKeyPath<PropFirmAccountRules, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard let rules = draft.propFirmRules, let value = rules[keyPath: keyPath] else { return "" }
                return String(value)
            },
            set: { raw in
                var rules = draft.propFirmRules ?? PropFirmAccountRules()
                let digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                rules[keyPath: keyPath] = digits.isEmpty ? nil : Int(digits)
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
