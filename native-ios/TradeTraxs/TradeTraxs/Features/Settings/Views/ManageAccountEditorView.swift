import SwiftUI

/// Add / Edit Account — web `CreateAccountModal` fields, native form.
struct ManageAccountEditorView: View {
    enum Mode {
        case create
        case edit(TradingAccountID)
    }

    @Bindable var viewModel: ManageAccountsViewModel
    let mode: Mode
    @State private var draft: TradingAccountDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    init(viewModel: ManageAccountsViewModel, mode: Mode, draft: TradingAccountDraft) {
        self.viewModel = viewModel
        self.mode = mode
        _draft = State(initialValue: draft)
    }

    private var title: String {
        switch mode {
        case .create: return "Add Account"
        case .edit: return "Edit Account"
        }
    }

    var body: some View {
        Form {
            Section("Account") {
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

                TextField("Account name", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("manageAccounts.name")

                TextField("Account value", text: $draft.sizeDigits)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("manageAccounts.size")

                TextField("Account ID (optional)", text: $draft.accountNumber)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if draft.category != .backtest {
                    Picker("Mode", selection: $draft.mode) {
                        ForEach(ManageAccountsViewModel.modes(for: draft.category), id: \.self) { mode in
                            Text(ManageAccountsViewModel.modeLabel(mode, category: draft.category))
                                .tag(mode)
                        }
                    }
                }

                TextField("Note (optional)", text: $draft.note, axis: .vertical)
                    .lineLimit(2...4)
            }

            if draft.category == .propFirm {
                Section("Prop Firm Rules") {
                    TextField(
                        "Max drawdown ($)",
                        text: bindingDecimal(\.maxDrawdown)
                    )
                    .keyboardType(.decimalPad)
                    TextField(
                        "Daily drawdown ($)",
                        text: bindingDecimal(\.dailyDrawdown)
                    )
                    .keyboardType(.decimalPad)
                    TextField(
                        "Profit target ($)",
                        text: bindingDecimal(\.profitTarget)
                    )
                    .keyboardType(.decimalPad)
                    TextField(
                        "Consistency (%)",
                        text: bindingDecimal(\.consistencyPercent)
                    )
                    .keyboardType(.decimalPad)
                    TextField(
                        "Winning days required",
                        text: bindingInt(\.winningDaysRequired)
                    )
                    .keyboardType(.numberPad)
                    TextField(
                        "Winning day threshold ($)",
                        text: bindingDecimal(\.winningDayThreshold)
                    )
                    .keyboardType(.decimalPad)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(mode.isCreate ? "Add" : "Save") {
                    Task { await save() }
                }
                .disabled(viewModel.isSaving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("manageAccounts.save")
            }
        }
        .disabled(viewModel.isSaving)
        .accessibilityIdentifier("manageAccounts.editor")
    }

    private func save() async {
        let ok: Bool
        switch mode {
        case .create:
            ok = await viewModel.create(draft)
        case .edit(let id):
            ok = await viewModel.update(id: id, draft: draft)
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
