import SwiftUI

/// Add / Edit Account, web `CreateAccountModal` fields, native form.
struct ManageAccountEditorView: View {
    enum Mode {
        case create
        case edit(TradingAccount)
        case graduate(TradingAccount)
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
    @State private var enableLiveDrawdownOnCreate = false
    @State private var liveDrawdownLimitDigits = ""
    @State private var liveDrawdownType: LivePersonalDrawdownType = .fixed
    @State private var liveDrawdownFloorCapDigits = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private let data: DataEnvironment?
    private let navigationCoordinator: NavigationCoordinator?
    private let brokerLinkContext: BrokerAccountLinkContext?
    private let onCreateSubmit: ((TradingAccountDraft, LivePersonalDrawdownConfig?) async -> Bool)?

    init(
        viewModel: ManageAccountsViewModel,
        mode: Mode,
        draft: TradingAccountDraft,
        data: DataEnvironment? = nil,
        navigationCoordinator: NavigationCoordinator? = nil,
        brokerLinkContext: BrokerAccountLinkContext? = nil,
        onCreateSubmit: ((TradingAccountDraft, LivePersonalDrawdownConfig?) async -> Bool)? = nil
    ) {
        self.viewModel = viewModel
        self.mode = mode
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.brokerLinkContext = brokerLinkContext
        self.onCreateSubmit = onCreateSubmit
        _draft = State(initialValue: draft)
        if case .edit(let account) = mode {
            _showInAccountDropdowns = State(initialValue: account.showInAccountDropdowns)
            _customPublicStatus = State(initialValue: account.customPublicStatus ?? "")
            if account.mode == .backtest {
                let gear = LivePersonalDrawdownEngine.gearDraft(
                    from: account,
                    eligibility: .backtestAccount
                )
                _liveDrawdownLimitDigits = State(initialValue: gear.limitDigits)
                _liveDrawdownFloorCapDigits = State(initialValue: gear.floorCapDigits)
                _liveDrawdownType = State(initialValue: gear.limitType)
            }
        }
    }

    private var title: String {
        switch mode {
        case .create:
            return brokerLinkContext == nil ? "Add Account" : "Create & Link Account"
        case .edit: return "Edit Account"
        case .graduate: return "Upgrade to Funded"
        }
    }

    private var saveAccountID: TradingAccountID? {
        if case .edit(let account) = mode { return account.id }
        return nil
    }

    /// Add Account type picker only; Edit Account keeps ``Backtest`` for existing backtest accounts.
    private var addAccountBacktestTypeLabel: String {
        guard case .create = mode else { return "Backtest" }
        if ProAccessGate.shouldPresentPaywall(profileID: viewModel.viewerProfileID) {
            return "Backtest (Pro)"
        }
        return "Backtest"
    }

    private var showsAccountValueInfo: Bool {
        draft.category == .personal || draft.category == .broker || draft.category == .backtest
    }

    private static let accountValueInfoBody =
        "Account Value is the starting balance for equity and drawdown tracking. "
            + "Use the amount you began trading with, not current equity or imported P&L."

    private static let enableDrawdownInfoBody =
        "Informational drawdown floor on the Dashboard equity curve. "
            + "You can change these settings later from the equity chart."

    private static let backtestDrawdownInfoBody =
        "Optional drawdown floor on the Backtest Lab equity curve. Requires Account Value when enabled."

    var body: some View {
        Form {
            if let brokerLinkContext {
                Section {
                    BrokerDiscoveredAccountSummaryCard(
                        provider: brokerLinkContext.provider,
                        account: brokerLinkContext.account
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Broker account")
                } footer: {
                    Text("Finish setting up your TradeTraxs account to link it to this broker login.")
                }
            }

            if case .edit = mode {
                Section {
                    Toggle("Display in Account Dropdowns", isOn: $showInAccountDropdowns)
                        .accessibilityIdentifier("manageAccounts.showInDropdowns")
                        .manageAccountFormRow()
                } header: {
                    sectionHeader("Visibility")
                } footer: {
                    Text("Hide this account from account selectors without deleting its data.")
                }
            }

            Section {
                Picker("Type", selection: $draft.category) {
                    Text("Personal").tag(TradingAccountCategory.personal)
                    Text("Broker").tag(TradingAccountCategory.broker)
                    Text("Prop Firm").tag(TradingAccountCategory.propFirm)
                    Text(addAccountBacktestTypeLabel).tag(TradingAccountCategory.backtest)
                }
                .manageAccountFormRow()
                .onChange(of: draft.category) { previous, category in
                    if category == .backtest,
                       ProAccessGate.presentFeatureIfNeeded(
                           .backtestLab,
                           profileID: viewModel.viewerProfileID
                       ) {
                        draft.category = previous
                        return
                    }
                    draft.mode = ManageAccountsViewModel.defaultMode(for: category)
                    if category != .propFirm {
                        draft.propFirmRules = nil
                    } else if draft.propFirmRules == nil {
                        draft.propFirmRules = PropFirmAccountRules()
                    }
                }

                accountField("Account Name") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("manageAccounts.name")
                }
                .manageAccountFormRow()

                HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                    accountField(
                        "Account Value",
                        infoTitle: showsAccountValueInfo ? "Account Value" : nil,
                        infoBody: showsAccountValueInfo ? Self.accountValueInfoBody : nil,
                        infoAccessibilityID: showsAccountValueInfo ? "manageAccounts.accountValue.info" : nil
                    ) {
                        TextField("0", text: $draft.sizeDigits.numericInput(.accountSize))
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("manageAccounts.size")
                    }
                    accountField("Account ID") {
                        TextField("Optional", text: $draft.accountNumber)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .manageAccountFormRow()

                if draft.category != .backtest {
                    Picker("Mode", selection: $draft.mode) {
                        ForEach(ManageAccountsViewModel.modes(for: draft.category), id: \.self) { mode in
                            Text(ManageAccountsViewModel.modeLabel(mode, category: draft.category))
                                .tag(mode)
                        }
                    }
                    .manageAccountFormRow()
                }

                if showsBacktestDrawdownEditSection {
                    accountField(
                        "Drawdown",
                        infoTitle: "Enable Drawdown",
                        infoBody: Self.backtestDrawdownInfoBody,
                        infoAccessibilityID: "manageAccounts.backtestDrawdown.info"
                    ) {
                        EmptyView()
                    }
                    .manageAccountFormRow()

                    Picker("Drawdown Type", selection: $liveDrawdownType) {
                        ForEach(LivePersonalDrawdownType.allCases, id: \.self) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    .manageAccountFormRow()
                    .accessibilityIdentifier("manageAccounts.backtestDrawdown.type")

                    if liveDrawdownType == .trailing {
                        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                            accountField("Max Drawdown") {
                                NumericAdornedTextField(
                                    placeholder: "0",
                                    text: $liveDrawdownLimitDigits,
                                    style: .unsignedCurrency,
                                    adornment: .currencyPrefix
                                )
                                .accessibilityIdentifier("manageAccounts.backtestDrawdown.limit")
                            }
                            accountField("Trailing Drawdown Cap") {
                                NumericAdornedTextField(
                                    placeholder: "Optional",
                                    text: $liveDrawdownFloorCapDigits,
                                    style: .unsignedCurrency,
                                    adornment: .currencyPrefix
                                )
                                .accessibilityIdentifier("manageAccounts.backtestDrawdown.floorCap")
                            }
                        }
                        .manageAccountFormRow()
                    } else {
                        accountField("Max Drawdown") {
                            NumericAdornedTextField(
                                placeholder: "0",
                                text: $liveDrawdownLimitDigits,
                                style: .unsignedCurrency,
                                adornment: .currencyPrefix
                            )
                            .accessibilityIdentifier("manageAccounts.backtestDrawdown.limit")
                        }
                        .manageAccountFormRow()
                    }
                }

                if showsLiveDrawdownOnCreateSection {
                    Toggle(isOn: $enableLiveDrawdownOnCreate) {
                        accountFieldLabel(
                            title: "Enable Drawdown",
                            infoTitle: "Enable Drawdown",
                            infoBody: Self.enableDrawdownInfoBody,
                            infoAccessibilityID: "manageAccounts.liveDrawdown.enableInfo"
                        )
                    }
                    .manageAccountFormRow()
                    .accessibilityIdentifier("manageAccounts.liveDrawdown.enable")

                    if enableLiveDrawdownOnCreate {
                        Picker("Drawdown Type", selection: $liveDrawdownType) {
                            ForEach(LivePersonalDrawdownType.allCases, id: \.self) { kind in
                                Text(kind.displayTitle).tag(kind)
                            }
                        }
                        .manageAccountFormRow()
                        .accessibilityIdentifier("manageAccounts.liveDrawdown.type")

                        if liveDrawdownType == .trailing {
                            HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                                accountField("Max Drawdown") {
                                    NumericAdornedTextField(
                                        placeholder: "0",
                                        text: $liveDrawdownLimitDigits,
                                        style: .unsignedCurrency,
                                        adornment: .currencyPrefix
                                    )
                                    .accessibilityIdentifier("manageAccounts.liveDrawdown.limit")
                                }
                                accountField("Trailing Drawdown Cap") {
                                    NumericAdornedTextField(
                                        placeholder: "Optional",
                                        text: $liveDrawdownFloorCapDigits,
                                        style: .unsignedCurrency,
                                        adornment: .currencyPrefix
                                    )
                                    .accessibilityIdentifier("manageAccounts.liveDrawdown.floorCap")
                                }
                            }
                            .manageAccountFormRow()
                        } else {
                            accountField("Max Drawdown") {
                                NumericAdornedTextField(
                                    placeholder: "0",
                                    text: $liveDrawdownLimitDigits,
                                    style: .unsignedCurrency,
                                    adornment: .currencyPrefix
                                )
                                .accessibilityIdentifier("manageAccounts.liveDrawdown.limit")
                            }
                            .manageAccountFormRow()
                        }
                    }
                }

                if draft.category == .propFirm,
                   draft.mode == .evaluation || draft.mode == .funded {
                    accountField("Account Purchase Cost") {
                        NumericAdornedTextField(
                            placeholder: "Optional",
                            text: $draft.purchaseCostDigits,
                            style: .unsignedCurrency,
                            adornment: .currencyPrefix
                        )
                        .accessibilityIdentifier("manageAccounts.purchaseCost")
                    }
                    .manageAccountFormRow()
                    DatePicker(
                        "Purchase Date",
                        selection: purchaseDateBinding,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .manageAccountFormRow()
                    .accessibilityIdentifier("manageAccounts.purchaseDate")
                }

                accountField("Note") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                }
                .manageAccountFormRow()
            } header: {
                sectionHeader("Account")
            }

            if draft.category == .propFirm {
                Section {
                    HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                        accountField("Max Drawdown") {
                            NumericAdornedTextField(
                                placeholder: "0",
                                text: bindingDecimal(\.maxDrawdown),
                                adornment: .currencyPrefix
                            )
                        }
                        accountField("Daily Drawdown") {
                            NumericAdornedTextField(
                                placeholder: "0",
                                text: bindingDecimal(\.dailyDrawdown),
                                adornment: .currencyPrefix
                            )
                        }
                    }
                    .manageAccountFormRow()

                    Picker("Drawdown Type", selection: bindingDrawdownType()) {
                        Text("Unspecified").tag(Optional<PropFirmDrawdownType>.none)
                        ForEach(PropFirmDrawdownType.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(Optional(kind))
                        }
                    }
                    .manageAccountFormRow()

                    HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                        accountField("Profit Target") {
                            NumericAdornedTextField(
                                placeholder: "0",
                                text: bindingDecimal(\.profitTarget),
                                adornment: .currencyPrefix
                            )
                        }
                        accountField("Consistency (%)") {
                            NumericAdornedTextField(
                                placeholder: "0",
                                text: bindingDecimal(\.consistencyPercent),
                                adornment: .percentSuffix
                            )
                        }
                    }
                    .manageAccountFormRow()

                    HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                        accountField("Winning Days") {
                            TextField("0", text: bindingInt(\.winningDaysRequired))
                                .keyboardType(.numberPad)
                                .accessibilityLabel("Winning days required")
                        }
                        accountField("Day Threshold ($)") {
                            NumericAdornedTextField(
                                placeholder: "0",
                                text: bindingDecimal(\.winningDayThreshold),
                                adornment: .currencyPrefix
                            )
                            .accessibilityLabel("Winning day threshold")
                        }
                    }
                    .manageAccountFormRow()
                } header: {
                    sectionHeader("Prop Firm Rules")
                }
            }

            if case .edit(let account) = mode {
                Section {
                    accountField(
                        "Public Status",
                        caption: "Optional label on your profile"
                    ) {
                        TextField("Passed, Funded, Blown", text: $customPublicStatus)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("manageAccounts.publicStatus")
                    }
                    .manageAccountFormRow()
                } header: {
                    sectionHeader("Profile")
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
                        .manageAccountFormRow()
                    } header: {
                        sectionHeader("Payout Cycle")
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
                        sectionHeader("Manual Payouts")
                    } footer: {
                        Text("Private to you. Share payouts publicly by posting payout achievements.")
                    }
                } else if !PropFirmPayoutPolicy.supportsRecordPayout(for: account) {
                    Section {
                        Text("Payout recording is not available for evaluation, simulated, or backtest accounts.")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                            .manageAccountFormRow()
                    } header: {
                        sectionHeader("Payouts")
                    }
                }
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .foregroundStyle(colors.loss)
                        .font(.footnote)
                        .accessibilityIdentifier("manageAccounts.formError")
                        .manageAccountFormRow()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .experienceTradeTraxsFormStyle(pageBackground: false)
        .experienceScreenBackground()
        .listSectionSpacing(ExperienceSpacing.xxs)
        .contentMargins(.top, ExperienceSpacing.xxs, for: .scrollContent)
        .experienceNavigationTitle(title)
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
            if let account, PropFirmPayoutPolicy.supportsManualPayoutLedger(for: account) {
                await viewModel.loadPayoutEntries(for: accountID)
            }
            await loadAccountPurchaseCost(accountID: accountID)
        }
        .onChange(of: viewModel.accounts) { _, _ in
            syncInsightsFromViewModel()
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .padding(.top, -ExperienceSpacing.xxs)
    }

    @ViewBuilder
    private func accountFieldLabel(
        title: String,
        infoTitle: String? = nil,
        infoBody: String? = nil,
        infoAccessibilityID: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if let infoTitle, let infoBody {
                AnalyticsMetricInfoButton(
                    title: infoTitle,
                    bodyText: infoBody,
                    accessibilityID: infoAccessibilityID
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountField<Content: View>(
        _ title: String,
        caption: String? = nil,
        infoTitle: String? = nil,
        infoBody: String? = nil,
        infoAccessibilityID: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            accountFieldLabel(
                title: title,
                infoTitle: infoTitle,
                infoBody: infoBody,
                infoAccessibilityID: infoAccessibilityID
            )
            content()
            if let caption {
                Text(caption)
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func loadAccountPurchaseCost(accountID: TradingAccountID) async {
        guard let data else { return }
        guard draft.category == .propFirm,
              draft.mode == .evaluation || draft.mode == .funded
        else { return }
        guard draft.purchaseCostDigits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let expense = try? await PropFirmExpenseRepository(supabase: data.supabase)
            .accountPurchaseExpense(accountID: accountID)
        else { return }
        draft.purchaseCostDigits = PropFirmExpenseMoney.editingText(expense.costPerAccount)
        if draft.purchaseDate == nil, let date = PropFirmExpenseMoney.date(fromDay: expense.datePaid) {
            draft.purchaseDate = date
        }
    }

    private var purchaseDateBinding: Binding<Date> {
        Binding(
            get: { draft.purchaseDate ?? .now },
            set: { draft.purchaseDate = $0 }
        )
    }

    private var showsLiveDrawdownOnCreateSection: Bool {
        guard case .create = mode else { return false }
        if draft.category == .backtest { return true }
        guard draft.category == .personal || draft.category == .broker else { return false }
        return draft.mode == .live
    }

    private var showsBacktestDrawdownEditSection: Bool {
        guard case .edit(let account) = mode else { return false }
        return account.mode == .backtest
    }

    private enum LiveDrawdownCreateResolution {
        case skip
        case apply(LivePersonalDrawdownConfig)
        case invalid(String)
    }

    private enum LiveDrawdownEditResolution {
        case skip
        case apply(LivePersonalDrawdownConfig)
        case clear
        case invalid(String)
    }

    private func resolveLiveDrawdownForEditBacktest() -> LiveDrawdownEditResolution {
        switch LivePersonalDrawdownEngine.parseGearDraft(
            limitDigits: liveDrawdownLimitDigits,
            limitType: liveDrawdownType,
            floorCapDigits: liveDrawdownFloorCapDigits,
            includeFloorCapField: liveDrawdownType == .trailing,
            limitPolicy: .clearWhenEmptyOrZero
        ) {
        case .success(nil):
            return .clear
        case .success(let config):
            guard let config else { return .clear }
            return .apply(config)
        case .failure(let error):
            return .invalid(error.message)
        }
    }

    private func resolveLiveDrawdownForCreate() -> LiveDrawdownCreateResolution {
        guard showsLiveDrawdownOnCreateSection else { return .skip }
        if draft.category != .backtest, !enableLiveDrawdownOnCreate {
            return .skip
        }
        if draft.category == .backtest, !enableLiveDrawdownOnCreate {
            return .skip
        }
        switch LivePersonalDrawdownEngine.parseGearDraft(
            limitDigits: liveDrawdownLimitDigits,
            limitType: liveDrawdownType,
            floorCapDigits: liveDrawdownFloorCapDigits,
            includeFloorCapField: liveDrawdownType == .trailing,
            limitPolicy: .requirePositiveLimit
        ) {
        case .success(let config):
            guard let config else {
                return .invalid("Enter a drawdown limit greater than zero.")
            }
            return .apply(config)
        case .failure(let error):
            return .invalid(error.message)
        }
    }

    private func save() async {
        viewModel.clearFormError()
        var ok: Bool
        switch mode {
        case .create:
            let liveDrawdownConfig: LivePersonalDrawdownConfig?
            switch resolveLiveDrawdownForCreate() {
            case .skip:
                liveDrawdownConfig = nil
            case .apply(let config):
                liveDrawdownConfig = config
            case .invalid(let message):
                viewModel.noteFormValidationError(message)
                return
            }
            if let onCreateSubmit {
                ok = await onCreateSubmit(draft, liveDrawdownConfig)
            } else {
                ok = await viewModel.create(draft, livePersonalDrawdown: liveDrawdownConfig)
            }
        case .graduate(let evaluation):
            ok = await viewModel.graduateEvaluationToFunded(evaluation: evaluation, draft: draft)
        case .edit(let account):
            ok = await viewModel.update(id: account.id, draft: draft)
            if ok, account.mode == .backtest {
                switch resolveLiveDrawdownForEditBacktest() {
                case .skip:
                    break
                case .apply(let config):
                    ok = await viewModel.applyLivePersonalDrawdown(accountID: account.id, config: config)
                case .clear:
                    ok = await viewModel.applyLivePersonalDrawdownClearing(accountID: account.id)
                case .invalid(let message):
                    viewModel.noteFormValidationError(message)
                    ok = false
                }
            }
            if ok {
                ok = await viewModel.updateInsightsSettings(
                    accountID: account.id,
                    showInAccountDropdowns: showInAccountDropdowns,
                    customPublicStatus: customPublicStatus
                )
            }
        }
        if ok {
            let toast: String = {
                switch mode {
                case .create, .graduate:
                    return SaveSuccessToastMessage.changesSaved
                case .edit:
                    return SaveSuccessToastMessage.settingsSaved
                }
            }()
            SaveSuccessConfirmationCenter.shared.present(toast)
            dismiss()
        }
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

private enum ManageAccountFormLayout {
    static let rowInsets = EdgeInsets(
        top: ExperienceSpacing.xxs,
        leading: ExperienceSpacing.md,
        bottom: ExperienceSpacing.xxs,
        trailing: ExperienceSpacing.md
    )
}

private extension View {
    /// Same grouped cards as Add Trade. Light mode paints an explicit card so the boxes stay visible.
    func manageAccountFormRow() -> some View {
        modifier(ManageAccountFormRowModifier())
    }
}

private struct ManageAccountFormRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .experienceDashboardListRow()
                .listRowInsets(ManageAccountFormLayout.rowInsets)
        } else {
            content
                .listRowBackground(colors.cardBackground)
                .listRowInsets(ManageAccountFormLayout.rowInsets)
        }
    }
}
