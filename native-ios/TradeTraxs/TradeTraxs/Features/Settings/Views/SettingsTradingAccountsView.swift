import SwiftUI

/// Single Manage Accounts experience, Settings, Dashboard, and Calendar all land here.
struct SettingsTradingAccountsView: View {
    @State private var viewModel: ManageAccountsViewModel
    @State private var editorPresentation: EditorPresentation?
    @State private var showsUnsavedAccountDisplayDialog = false
    @State private var unsavedNavigationIntercept = TradingRulesUnsavedNavigationGuard.UnsavedNavigationInterceptBox()

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    private let data: DataEnvironment?
    private let navigationCoordinator: NavigationCoordinator?

    private enum EditorPresentation: Identifiable {
        case create
        case edit(TradingAccount)
        case graduate(TradingAccount)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let account): return "edit.\(account.id.rawValue)"
            case .graduate(let account): return "graduate.\(account.id.rawValue)"
            }
        }
    }

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator? = nil) {
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: ManageAccountsViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
        self.data = data
    }

    init(viewModel: ManageAccountsViewModel) {
        self.data = nil
        self.navigationCoordinator = nil
        _viewModel = State(initialValue: viewModel)
    }

    private var showsFreePlanTradeEntryReconfigure: Bool {
        guard let profileID = viewModel.viewerProfileID else { return false }
        guard !TradeEntryEntitlementGate.viewerHasTraxProAccess(profileID: profileID) else {
            return false
        }
        return viewModel.distinctAccountSlotCount > FreeTierPolicy.maxTradeEntryAccounts
    }

    /// Free viewers only. Pro keeps the single "Your Accounts" list.
    private var showsFreePlanAccountGroups: Bool {
        guard let profileID = viewModel.viewerProfileID else { return false }
        return !TradeEntryEntitlementGate.viewerHasTraxProAccess(profileID: profileID)
    }

    private var freePlanActiveSlotCount: Int {
        FreePlanTradeAccountPolicy.countTradeEntryEnabled(viewModel.accounts)
    }

    private var freePlanActiveAccounts: [TradingAccount] {
        viewModel.filteredAccounts.filter(FreePlanTradeAccountPolicy.accountCanAddTrades)
    }

    private var freePlanReadOnlyAccounts: [TradingAccount] {
        viewModel.filteredAccounts.filter { !FreePlanTradeAccountPolicy.accountCanAddTrades($0) }
    }

    var body: some View {
        List {
            if !viewModel.accounts.isEmpty {
                Section {
                    ManageAccountsFilterBar(viewModel: viewModel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(
                            EdgeInsets(
                                top: ExperienceSpacing.xs,
                                leading: ExperienceSpacing.md,
                                bottom: ExperienceSpacing.xxs,
                                trailing: ExperienceSpacing.md
                            )
                        )
                        .listRowBackground(colors.backgroundPrimary)
                        .listRowSeparator(.hidden)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            if let formError = viewModel.formError {
                Section {
                    Text(formError)
                        .experienceStyle(.footnote, color: colors.loss)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("manageAccounts.saveAccountDisplay.error")
                }
            }

            if let data, !AppLaunchController.shared.isDemoExperienceActive {
                Section {
                    NavigationLink {
                        BrokerIntegrationsView(data: data, navigationCoordinator: navigationCoordinator)
                    } label: {
                        brokerIntegrationsRow
                    }
                    .experienceDashboardListRow()
                    .accessibilityIdentifier("settings.tradingAccounts.brokerIntegrations")
                    NavigationLink {
                        CopyTradingAccountsView(data: data)
                    } label: {
                        copyTradingAccountsRow
                    }
                    .experienceDashboardListRow()
                    .accessibilityIdentifier("settings.tradingAccounts.copyTradingAccounts")
                } header: {
                    Text("Broker Integrations")
                }
            }

            if viewModel.showsFilteredEmptyState {
                Section {
                    SettingsIntroBlock(
                        title: "No matching accounts",
                        message: "Try changing your Prop Firm or Account Type filter."
                    )
                    Button("Clear Filters") {
                        viewModel.clearFilters()
                    }
                    .accessibilityIdentifier("manageAccounts.clearFilters")
                } header: {
                    yourAccountsSectionHeader
                }
            } else if viewModel.accounts.isEmpty, !viewModel.isLoading {
                Section {
                    ExperienceEmptyState(
                        icon: .payouts,
                        title: "No trading accounts yet",
                        message: "Add an account to organize trades by broker or prop firm."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    yourAccountsSectionHeader
                }
            } else if showsFreePlanAccountGroups {
                freePlanGroupedAccountSections
            } else {
                Section {
                    ForEach(viewModel.managementRows) { row in
                        switch row {
                        case .standalone(let account):
                            accountRow(account, tradeEntryBadge: nil)
                        case .lifecycle(let funded, let evaluation):
                            accountRow(funded, tradeEntryBadge: nil)
                            if let evaluation {
                                accountRow(evaluation, tradeEntryBadge: .readOnly)
                                    .padding(.leading, ExperienceSpacing.md)
                            }
                        }
                    }
                } header: {
                    yourAccountsSectionHeader
                }
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: false)
        .listSectionSpacing(ExperienceSpacing.xxs)
        .contentMargins(.top, viewModel.accounts.isEmpty ? ExperienceSpacing.xs : 0, for: .scrollContent)
        .experienceNavigationTitle("Manage Accounts")
        .navigationBarBackButtonHidden(viewModel.hasUnsavedAccountDisplayChanges)
        .background {
            TradingRulesUnsavedNavigationGuard(
                isActive: viewModel.hasUnsavedAccountDisplayChanges,
                interceptBox: unsavedNavigationIntercept
            )
            .equatable()
        }
        .onAppear {
            unsavedNavigationIntercept.onIntercept = { showsUnsavedAccountDisplayDialog = true }
        }
        .confirmationDialog(
            "Unsaved Changes",
            isPresented: $showsUnsavedAccountDisplayDialog,
            titleVisibility: .visible
        ) {
            Button("Save & Exit") {
                Task { await saveAccountDisplayAndExit() }
            }
            Button("Discard Changes", role: .destructive) {
                viewModel.discardAccountDisplayDraft()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved account display changes. Save before leaving?")
        }
        .toolbar {
            if viewModel.hasUnsavedAccountDisplayChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsUnsavedAccountDisplayDialog = true
                    } label: {
                        HStack(spacing: ExperienceSpacing.xxs) {
                            Image(systemName: "chevron.backward")
                                .fontWeight(.semibold)
                            Text("Back")
                        }
                    }
                    .accessibilityIdentifier("manageAccounts.back")
                }
            }
            if !AppLaunchController.shared.isDemoExperienceActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorPresentation = .create
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("manageAccounts.add")
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ExperienceIndeterminateProgress()
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            NavigationStack {
                switch presentation {
                case .create:
                    ManageAccountEditorView(
                        viewModel: viewModel,
                        mode: .create,
                        draft: viewModel.emptyDraft(),
                        data: data,
                        navigationCoordinator: navigationCoordinator
                    )
                case .edit(let account):
                    ManageAccountEditorView(
                        viewModel: viewModel,
                        mode: .edit(account),
                        draft: viewModel.draft(from: account),
                        data: data,
                        navigationCoordinator: navigationCoordinator
                    )
                case .graduate(let account):
                    ManageAccountEditorView(
                        viewModel: viewModel,
                        mode: .graduate(account),
                        draft: viewModel.fundedUpgradeDraft(from: account),
                        data: data,
                        navigationCoordinator: navigationCoordinator
                    )
                }
            }
            .experienceSheetChrome()
            .experienceProtectedFormDismiss()
        }
        .onAppear { viewModel.loadIfNeeded() }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            guard !viewModel.hasUnsavedAccountDisplayChanges else { return }
            Task { await viewModel.refresh() }
        }
        .accessibilityIdentifier("settings.tradingAccounts")
    }

    private var yourAccountsSectionHeader: some View {
        ManageAccountsYourAccountsSectionHeader(
            showsSave: !AppLaunchController.shared.isDemoExperienceActive && !viewModel.accounts.isEmpty,
            hasUnsavedChanges: viewModel.hasUnsavedAccountDisplayChanges,
            isSaving: viewModel.isSavingAccountDisplay,
            onSave: {
                Task { await saveAccountDisplayAndStay() }
            }
        )
    }

    private func saveAccountDisplayAndStay() async {
        let saved = await viewModel.saveAccountDisplayPreferences()
        if saved {
            SaveSuccessConfirmationCenter.shared.present(SaveSuccessToastMessage.settingsSaved)
        }
    }

    private func saveAccountDisplayAndExit() async {
        let saved = await viewModel.saveAccountDisplayPreferences()
        if saved {
            SaveSuccessConfirmationCenter.shared.present(SaveSuccessToastMessage.settingsSaved)
            dismiss()
        }
    }

    private enum TradeEntryAccountBadge {
        case active
        case readOnly
    }

    @ViewBuilder
    private var freePlanGroupedAccountSections: some View {
        if showsFreePlanTradeEntryReconfigure {
            Section {
                Button("Choose accounts for new trades") {
                    FreePlanAccountSlotRequestStore.shared.requestManualOpen()
                }
                .accessibilityIdentifier("manageAccounts.chooseTradeEntrySlots")
            } header: {
                yourAccountsSectionHeader
            }
        }

        if !freePlanActiveAccounts.isEmpty {
            Section {
                ForEach(freePlanActiveAccounts) { account in
                    accountRow(account, tradeEntryBadge: .active)
                }
            } header: {
                freePlanActiveAccountsSectionHeader
            }
        }

        if !freePlanReadOnlyAccounts.isEmpty {
            Section {
                ForEach(freePlanReadOnlyAccounts) { account in
                    accountRow(account, tradeEntryBadge: .readOnly)
                }
            } header: {
                freePlanReadOnlyAccountsSectionHeader
            }
        }
    }

    @ViewBuilder
    private var freePlanActiveAccountsSectionHeader: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            if !showsFreePlanTradeEntryReconfigure {
                yourAccountsSectionHeader
            }
            Text("Active Accounts (\(freePlanActiveSlotCount)/\(FreeTierPolicy.maxTradeEntryAccounts))")
        }
    }

    @ViewBuilder
    private var freePlanReadOnlyAccountsSectionHeader: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            if !showsFreePlanTradeEntryReconfigure, freePlanActiveAccounts.isEmpty {
                yourAccountsSectionHeader
            }
            Text("Read-Only Accounts")
        }
    }

    private func accountRow(
        _ account: TradingAccount,
        tradeEntryBadge: TradeEntryAccountBadge?
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            CompactAccountDropdownToggle(
                isOn: Binding(
                    get: { viewModel.showInAccountDropdowns(for: account.id) },
                    set: { show in
                        guard !AppLaunchController.shared.isDemoExperienceActive else { return }
                        viewModel.setDraftShowInAccountDropdowns(id: account.id, show: show)
                    }
                ),
                accessibilityIdentifier:
                    "manageAccounts.showInDropdowns.\(account.id.rawValue)",
                isOnAccessibilityValue: viewModel.showInAccountDropdowns(
                    for: account.id
                )
            )

            if TradingAccountLifecyclePolicy.canUpgradeToFunded(account) {
                Button {
                    guard !AppLaunchController.shared.isDemoExperienceActive else { return }
                    editorPresentation = .graduate(account)
                } label: {
                    Text("Upgrade to Funded")
                        .experienceStyle(.footnote, color: colors.success)
                }
                .accessibilityIdentifier("manageAccounts.upgradeToFunded.\(account.id.rawValue)")
            }

            Button {
                guard !AppLaunchController.shared.isDemoExperienceActive else { return }
                if TradingAccountLifecyclePolicy.isCompletedEvaluation(account) { return }
                editorPresentation = .edit(account)
            } label: {
                HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        HStack(spacing: ExperienceSpacing.xs) {
                            Text(viewModel.rowTitle(for: account))
                                .experienceStyle(.body, color: colors.primaryText)
                            if let tradeEntryBadge {
                                tradeEntryStatusBadge(tradeEntryBadge)
                            }
                        }
                        Text(viewModel.rowSubtitle(for: account))
                            .experienceStyle(.footnote, color: colors.secondaryText)
                        if let note = account.note, !note.isEmpty {
                            Text(note)
                                .experienceStyle(.caption, color: colors.tertiaryText)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: ExperienceSpacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .padding(.vertical, ExperienceSpacing.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)
        }
        .accessibilityIdentifier("settings.account.\(account.id.rawValue)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if AppLaunchController.shared.isDemoExperienceActive {
                EmptyView()
            } else {
                Button {
                    ExperienceHaptics.play(.selection)
                    Task {
                        await viewModel.setActive(id: account.id, isActive: !account.isActive)
                    }
                } label: {
                    Text(account.isActive ? "Deactivate" : "Activate")
                }
                .tint(account.isActive ? colors.secondaryText : colors.accent)
            }
        }
        .contextMenu {
            if !AppLaunchController.shared.isDemoExperienceActive {
                Button {
                    editorPresentation = .edit(account)
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                Button {
                    ExperienceHaptics.play(.selection)
                    Task {
                        await viewModel.setActive(id: account.id, isActive: !account.isActive)
                    }
                } label: {
                    Label(
                        account.isActive ? "Deactivate" : "Activate",
                        systemImage: account.isActive ? "pause.circle" : "checkmark.circle"
                    )
                }
            }
        }
    }

    private func tradeEntryStatusBadge(_ badge: TradeEntryAccountBadge) -> some View {
        let title = badge == .active ? "Active" : "Read-Only"
        let tint = badge == .active ? colors.accent : colors.secondaryText
        return Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(badge == .active ? "Active account" : "Read-only account")
    }


    private var brokerIntegrationsRow: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: "link.circle")
                .font(.body.weight(.medium))
                .foregroundStyle(colors.accent)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Broker Integrations")
                    .experienceStyle(.body, color: colors.primaryText)
                Text("Connect & import trades")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer(minLength: ExperienceSpacing.xs)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .contentShape(Rectangle())
    }

    private var copyTradingAccountsRow: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: "square.on.square")
                .font(.body.weight(.medium))
                .foregroundStyle(colors.accent)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Copy Trading Accounts")
                    .experienceStyle(.body, color: colors.primaryText)
                Text("Journal one trade across accounts")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer(minLength: ExperienceSpacing.xs)
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .contentShape(Rectangle())
    }
}

private struct ManageAccountsYourAccountsSectionHeader: View {
    private static let infoMessage =
        "Choose which accounts appear in selectors across TradeTraxs. Toggle each account on or off, then tap Save."

    var showsSave: Bool
    var hasUnsavedChanges: Bool
    var isSaving: Bool
    var onSave: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xxs) {
                Text("Your Accounts")
                AnalyticsMetricInfoButton(
                    title: "Your Accounts",
                    bodyText: Self.infoMessage,
                    accessibilityID: "manageAccounts.dropdownIntro"
                )
            }
            Spacer(minLength: ExperienceSpacing.xs)
            if showsSave {
                Button(isSaving ? "Saving…" : "Save") {
                    onSave()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasUnsavedChanges ? colors.accent : colors.tertiaryText)
                .disabled(!hasUnsavedChanges || isSaving)
                .accessibilityIdentifier("manageAccounts.saveAccountDisplay")
            }
        }
    }
}
