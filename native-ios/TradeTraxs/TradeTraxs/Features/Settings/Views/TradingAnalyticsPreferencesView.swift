import SwiftUI

/// Settings editor for optional trading-analytics preferences.
struct TradingAnalyticsPreferencesView: View {
    @State private var viewModel: TradingAnalyticsPreferencesViewModel
    let navigationCoordinator: NavigationCoordinator
    @State private var showsInstrumentPicker = false
    @State private var showsUnsavedDialog = false
    @State private var unsavedNavigationIntercept = TradingRulesUnsavedNavigationGuard.UnsavedNavigationInterceptBox()
    @FocusState private var focusedField: TradingAnalyticsPreferencesViewModel.DraftField?
    @State private var generalExpanded = false
    @State private var riskExpanded = false
    @State private var executionExpanded = false
    @State private var disciplineExpanded = false
    @State private var sessionsExpanded = false
    @State private var accountOverridesExpanded = false
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private let embeddedInTraxsProRulesPreview: Bool

    init(data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.embeddedInTraxsProRulesPreview = false
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(initialValue: TradingAnalyticsPreferencesViewModel(
            repository: data.tradingPreferences,
            session: data.session,
            detailCache: data.detailCache,
            loadAccounts: { userID in
                try await data.trades.accounts(for: userID)
            }
        ))
    }

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        embeddedInTraxsProRulesPreview: Bool
    ) {
        self.embeddedInTraxsProRulesPreview = embeddedInTraxsProRulesPreview
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(initialValue: TradingAnalyticsPreferencesViewModel(
            repository: data.tradingPreferences,
            session: data.session,
            detailCache: data.detailCache,
            loadAccounts: { userID in
                try await data.trades.accounts(for: userID)
            },
            loadsTraxsProPreviewSample: embeddedInTraxsProRulesPreview
        ))
    }

    var body: some View {
        preferencesScroll
            .scrollDismissesKeyboard(.interactively)
            .experienceScreenBackground()
            .experienceKeyboardDoneToolbar()
            .experienceFormKeyboard(focus: $focusedField)
            .experienceNavigationTitle("Trading Rules")
            .toolbar {
                if !embeddedInTraxsProRulesPreview {
                    tradingRulesToolbar
                }
            }
            .navigationBarBackButtonHidden(!embeddedInTraxsProRulesPreview && viewModel.hasUnsavedChanges)
            .background {
                if !embeddedInTraxsProRulesPreview {
                    TradingRulesUnsavedNavigationGuard(
                        isActive: viewModel.hasUnsavedChanges,
                        interceptBox: unsavedNavigationIntercept
                    )
                    .equatable()
                }
            }
            .onAppear {
                guard !embeddedInTraxsProRulesPreview else { return }
                unsavedNavigationIntercept.onIntercept = { showsUnsavedDialog = true }
            }
            .confirmationDialog(
                "Unsaved Changes",
                isPresented: $showsUnsavedDialog,
                titleVisibility: .visible
            ) {
                Button("Save & Exit") {
                    Task { await saveAndExit() }
                }
                Button("Discard Changes", role: .destructive) {
                    viewModel.discardChanges()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved trading rules. Would you like to save before leaving?")
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .task {
                await viewModel.load()
                if embeddedInTraxsProRulesPreview {
                    generalExpanded = true
                    riskExpanded = true
                    executionExpanded = true
                    disciplineExpanded = true
                    sessionsExpanded = true
                }
            }
            .sheet(isPresented: $showsInstrumentPicker) {
                NavigationStack {
                    TradingPreferenceInstrumentPicker(viewModel: viewModel) {
                        showsInstrumentPicker = false
                    }
                }
            }
            .accessibilityIdentifier("settings.tradingAnalytics")
            .confirmationDialog(
                "Apply template?",
                isPresented: templateDialogBinding,
                titleVisibility: .visible
            ) {
                Button("Apply to draft") { viewModel.applyStagedTemplate() }
                Button("Cancel", role: .cancel) { viewModel.pendingTemplate = nil }
            } message: {
                templateDialogMessage
            }
    }

    private var restrictsPremiumRulesEditing: Bool {
        if embeddedInTraxsProRulesPreview { return false }
        let profileID = viewModel.preferences.userID.rawValue.isEmpty ? nil : viewModel.preferences.userID
        return ProMonetizationPolicy.shouldRestrictTradingRulesComplianceAnalytics(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
    }

    private var preferencesScroll: some View {
        ScrollView {
            LazyVStack(spacing: ExperienceSpacing.md) {
                if !embeddedInTraxsProRulesPreview {
                    tradingRulesAnalyticsLinkCard
                }
                statusMessageBanner
                if restrictsPremiumRulesEditing {
                    freeTierRulesEditor
                    TradingRulesPremiumLockedSection()
                } else {
                    generalSettingsCategory
                    riskManagementCategory
                    tradeExecutionCategory
                    disciplineCategory
                    sessionsAndInstrumentsCategory
                }
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.xs)
            .padding(.bottom, ExperienceSpacing.xl)
        }
    }

    private var tradingRulesAnalyticsLinkCard: some View {
        let cornerRadius = ExperienceDashboardSurface.cornerRadius(.featured)
        return Button {
            navigationCoordinator.pushTradingRulesAnalytics()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Text("View Trading Rules Analytics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .experienceTradingRulesCard(prominence: .featured)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("settings.tradingRules.openAnalytics")
    }

    @ViewBuilder
    private var statusMessageBanner: some View {
        if let message = viewModel.message {
            Text(message)
                .experienceStyle(.caption, color: colors.loss)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ExperienceSpacing.md)
                .experienceTradingRulesCard(prominence: .standard)
        }
    }

    private var freeTierRulesEditor: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Your rules")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(MonetizationPlanCopy.tradingRulesFreeTierSummary)
                .experienceStyle(.caption, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                dropdownRow(
                    "Preferred Trading Session",
                    info: .preferredSessions,
                    value: sessionSummary,
                    isPlaceholder: viewModel.preferences.preferredSessions.isEmpty,
                    identifier: "settings.tradingAnalytics.sessions"
                ) {
                    ForEach(TradingPreferenceRules.sessions, id: \.self) { session in
                        Button {
                            viewModel.toggleSession(session)
                        } label: {
                            let title = TradingSessionCatalog.displayTitle(for: session)
                            if viewModel.preferences.preferredSessions.contains(session) {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                }
                settingsInlineDivider()
                Button {
                    showsInstrumentPicker = true
                } label: {
                    dropdownLabel(
                        "Primary Instrument",
                        info: .primaryInstruments,
                        value: instrumentSummary,
                        isPlaceholder: viewModel.preferences.primaryInstruments.isEmpty
                    )
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("settings.tradingAnalytics.instruments")
                .tradingRulesSettingsRow()
                settingsInlineDivider()
                dropdownRow(
                    "Allowed Trading Days",
                    info: .allowedTradingDays,
                    value: allowedDaysSummary,
                    isPlaceholder: viewModel.preferences.allowedTradingDays.isEmpty,
                    identifier: "settings.tradingAnalytics.allowedDays"
                ) {
                    ForEach(TradingRuleWeekday.displayOrder, id: \.self) { day in
                        Button {
                            viewModel.toggleAllowedDay(day)
                        } label: {
                            if viewModel.preferences.allowedTradingDays.contains(day.rawValue) {
                                Label(day.displayLabel, systemImage: "checkmark")
                            } else {
                                Text(day.displayLabel)
                            }
                        }
                    }
                }
                settingsInlineDivider()
                scopedNumericField(
                    TradingRulesFieldInfo.maxTradesPerDay.title,
                    info: .maxTradesPerDay,
                    placeholder: "5",
                    text: $viewModel.maxTrades,
                    field: .maxTrades,
                    style: .unsignedInteger,
                    keyboard: .numberPad,
                    scope: $viewModel.maxTradesPerDayScope,
                    scopeIdentifier: "settings.tradingAnalytics.maxTradesScope"
                )
                settingsInlineDivider()
                numericField(
                    TradingRulesDisplayLabels.maxContracts,
                    info: .maxContractsPerTrade,
                    placeholder: "4",
                    text: $viewModel.maxContracts,
                    field: .maxContracts,
                    style: .unsignedInteger,
                    keyboard: .numberPad
                )
            }
            .experienceTradingRulesCard(prominence: .featured)
        }
    }

    private var generalSettingsCategory: some View {
        TradingRulesSettingsCategoryCard(
            title: TradingAnalyticsPreferencesViewModel.SettingsCategory.general.rawValue,
            configuredCount: viewModel.configuredRuleCount(for: .general),
            isExpanded: $generalExpanded,
            resetID: "settings.tradingAnalytics.general.reset",
            showsReset: false
        ) {
            EmptyView()
        } content: {
            VStack(spacing: 0) {
                templateDropdownRow
                settingsInlineDivider()
                generalBehaviorRows
            }
        }
    }

    @ViewBuilder
    private var generalBehaviorRows: some View {
        Toggle(isOn: $viewModel.applyRulesToPastTrades) {
            TradingRulesFieldLabel(
                title: "Apply Rules to Past Trades",
                info: .applyRulesToPastTrades
            )
        }
        .tint(colors.accent)
        .tradingRulesSettingsRow()
        .accessibilityIdentifier("settings.tradingAnalytics.applyPastTrades")

        settingsInlineDivider()

        numericField(
            "Personal compliance goal (%)",
            info: .personalComplianceGoal,
            placeholder: "90",
            text: $viewModel.complianceGoal,
            field: .complianceGoal,
            style: .unsignedInteger,
            keyboard: .numberPad
        )
    }

    private var riskManagementCategory: some View {
        TradingRulesSettingsCategoryCard(
            title: TradingAnalyticsPreferencesViewModel.SettingsCategory.riskManagement.rawValue,
            configuredCount: viewModel.configuredRuleCount(for: .riskManagement),
            isExpanded: $riskExpanded,
            resetID: "settings.tradingAnalytics.risk.reset"
        ) {
            Button("Daily loss limit") { viewModel.reset(\.dailyLossLimit) }
            Button(TradingRulesFieldInfo.maxRiskPerTrade.title) { viewModel.reset(\.maxRiskPerTrade) }
            Button("Breakeven tolerance") { viewModel.reset(\.breakevenTolerance) }
            Button(TradingRulesFieldInfo.maxWeeklyLoss.title) { viewModel.reset(\.maxWeeklyLoss) }
            Button(TradingRulesFieldInfo.maxDrawdownGoal.title) { viewModel.reset(\.maxDrawdownGoal) }
            Divider()
            Button("Reset global risk rules") {
                viewModel.reset(\.dailyLossLimit)
                viewModel.reset(\.maxRiskPerTrade)
                viewModel.reset(\.breakevenTolerance)
                viewModel.reset(\.maxWeeklyLoss)
                viewModel.reset(\.maxDrawdownGoal)
            }
        } content: {
            VStack(spacing: 0) {
                scopedNumericField(
                    "Daily loss limit",
                    info: .dailyLossLimit,
                    placeholder: "500",
                    text: $viewModel.dailyLoss,
                    field: .dailyLoss,
                    style: .propFirmAmount,
                    scope: $viewModel.dailyLossLimitScope,
                    scopeIdentifier: "settings.tradingAnalytics.dailyLossScope"
                )
                settingsInlineDivider()
                numericField(
                    TradingRulesFieldInfo.maxRiskPerTrade.title,
                    info: .maxRiskPerTrade,
                    placeholder: "250",
                    text: $viewModel.maxRisk,
                    field: .maxRisk,
                    style: .propFirmAmount
                )
                settingsInlineDivider()
                numericField(
                    "Breakeven tolerance",
                    info: .breakevenTolerance,
                    placeholder: "0",
                    text: $viewModel.breakeven,
                    field: .breakeven,
                    style: .propFirmAmount
                )
                settingsInlineDivider()
                scopedNumericField(
                    TradingRulesFieldInfo.maxWeeklyLoss.title,
                    info: .maxWeeklyLoss,
                    placeholder: "1500",
                    text: $viewModel.maxWeeklyLoss,
                    field: .maxWeeklyLoss,
                    style: .propFirmAmount,
                    scope: $viewModel.maxWeeklyLossScope,
                    scopeIdentifier: "settings.tradingAnalytics.weeklyLossScope"
                )
                settingsInlineDivider()
                numericField(
                    TradingRulesFieldInfo.maxDrawdownGoal.title,
                    info: .maxDrawdownGoal,
                    placeholder: "2000",
                    text: $viewModel.drawdownGoal,
                    field: .drawdownGoal,
                    style: .propFirmAmount
                )
                settingsInlineDivider()
                accountOverridesBlock
            }
        }
    }

    private var tradeExecutionCategory: some View {
        TradingRulesSettingsCategoryCard(
            title: TradingAnalyticsPreferencesViewModel.SettingsCategory.tradeExecution.rawValue,
            configuredCount: viewModel.configuredRuleCount(for: .tradeExecution),
            isExpanded: $executionExpanded,
            resetID: "settings.tradingAnalytics.rules.reset"
        ) {
            Button("Target R:R") { viewModel.reset(\.targetRr) }
            Button(TradingRulesFieldInfo.minAcceptableRr.title) { viewModel.reset(\.minAcceptableRr) }
            Button(TradingRulesFieldInfo.maxContractsPerTrade.title) { viewModel.reset(\.maxContractsPerTrade) }
            Button(TradingRulesFieldInfo.maxTradesPerDay.title) { viewModel.reset(\.maxTradesPerDay) }
            Divider()
            Button("Reset All") {
                viewModel.reset(\.targetRr)
                viewModel.reset(\.minAcceptableRr)
                viewModel.reset(\.maxContractsPerTrade)
                viewModel.reset(\.maxTradesPerDay)
                viewModel.maxTradesPerDayScope = .combined
            }
        } content: {
            VStack(spacing: 0) {
                numericField(
                    "Target R:R",
                    info: .targetRr,
                    placeholder: "2",
                    text: $viewModel.targetRr,
                    field: .targetRr,
                    style: .riskReward
                )
                settingsInlineDivider()
                numericField(
                    TradingRulesFieldInfo.minAcceptableRr.title,
                    info: .minAcceptableRr,
                    placeholder: "1.5",
                    text: $viewModel.minAcceptableRr,
                    field: .minAcceptableRr,
                    style: .riskReward
                )
                settingsInlineDivider()
                numericField(
                    TradingRulesFieldInfo.maxContractsPerTrade.title,
                    info: .maxContractsPerTrade,
                    placeholder: "4",
                    text: $viewModel.maxContracts,
                    field: .maxContracts,
                    style: .unsignedInteger,
                    keyboard: .numberPad
                )
                settingsInlineDivider()
                scopedNumericField(
                    TradingRulesFieldInfo.maxTradesPerDay.title,
                    info: .maxTradesPerDay,
                    placeholder: "5",
                    text: $viewModel.maxTrades,
                    field: .maxTrades,
                    style: .unsignedInteger,
                    keyboard: .numberPad,
                    scope: $viewModel.maxTradesPerDayScope,
                    scopeIdentifier: "settings.tradingAnalytics.maxTradesScope"
                )
            }
        }
    }

    private var disciplineCategory: some View {
        TradingRulesSettingsCategoryCard(
            title: TradingAnalyticsPreferencesViewModel.SettingsCategory.discipline.rawValue,
            configuredCount: viewModel.configuredRuleCount(for: .discipline),
            isExpanded: $disciplineExpanded,
            resetID: "settings.tradingAnalytics.advanced.reset"
        ) {
            Button("Consecutive losses before a break") { viewModel.reset(\.consecutiveLossPause) }
            Button("Waiting time after a loss") { viewModel.reset(\.waitAfterLossMinutes) }
            Button("Daily profit target") { viewModel.reset(\.dailyProfitTarget) }
            Button("Stop after daily profit target") {
                viewModel.stopAfterDailyProfitTarget = false
            }
            Divider()
            Button("Reset All") {
                viewModel.reset(\.consecutiveLossPause)
                viewModel.reset(\.waitAfterLossMinutes)
                viewModel.reset(\.dailyProfitTarget)
                viewModel.stopAfterDailyProfitTarget = false
                viewModel.dailyProfitRulesScope = .combined
            }
        } content: {
            VStack(spacing: 0) {
                numericField(
                    "Consecutive losses before a break",
                    info: .consecutiveLossPause,
                    placeholder: "3",
                    text: $viewModel.lossPause,
                    field: .lossPause,
                    style: .unsignedInteger,
                    keyboard: .numberPad
                )
                settingsInlineDivider()
                numericField(
                    "Waiting time after a loss",
                    info: .waitAfterLossMinutes,
                    placeholder: "15",
                    text: $viewModel.waitMinutes,
                    field: .waitMinutes,
                    style: .unsignedInteger,
                    keyboard: .numberPad
                )
                settingsInlineDivider()
                scopedNumericField(
                    "Daily profit target",
                    info: .dailyProfitTarget,
                    placeholder: "1000",
                    text: $viewModel.profitTarget,
                    field: .profitTarget,
                    style: .propFirmAmount,
                    scope: $viewModel.dailyProfitRulesScope,
                    scopeIdentifier: "settings.tradingAnalytics.profitRulesScope"
                )
                settingsInlineDivider()
                Toggle(isOn: $viewModel.stopAfterDailyProfitTarget) {
                    TradingRulesFieldLabel(
                        title: "Stop after daily profit target",
                        info: .stopAfterDailyProfitTarget
                    )
                }
                .tint(colors.accent)
                .tradingRulesSettingsRow()
            }
        }
    }

    private var sessionsAndInstrumentsCategory: some View {
        TradingRulesSettingsCategoryCard(
            title: TradingAnalyticsPreferencesViewModel.SettingsCategory.sessionsAndInstruments.rawValue,
            configuredCount: viewModel.configuredRuleCount(for: .sessionsAndInstruments),
            isExpanded: $sessionsExpanded,
            resetID: "settings.tradingAnalytics.preferences.reset"
        ) {
            Button("Preferred trading sessions") { viewModel.clearSessions() }
            Button("Primary instruments") { viewModel.clearInstruments() }
            Button("Allowed trading days") { viewModel.clearAllowedDays() }
            Button("Planned hours") { viewModel.resetHours() }
            Divider()
            Button("Reset All") { viewModel.resetTradingPreferences() }
        } content: {
            VStack(spacing: 0) {
                dropdownRow(
                    "Preferred Trading Sessions",
                    info: .preferredSessions,
                    value: sessionSummary,
                    isPlaceholder: viewModel.preferences.preferredSessions.isEmpty,
                    identifier: "settings.tradingAnalytics.sessions"
                ) {
                    ForEach(TradingPreferenceRules.sessions, id: \.self) { session in
                        Button {
                            viewModel.toggleSession(session)
                        } label: {
                            let title = TradingSessionCatalog.displayTitle(for: session)
                            if viewModel.preferences.preferredSessions.contains(session) {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                }
                settingsInlineDivider()
                Button {
                    showsInstrumentPicker = true
                } label: {
                    dropdownLabel(
                        "Primary Instruments",
                        info: .primaryInstruments,
                        value: instrumentSummary,
                        isPlaceholder: viewModel.preferences.primaryInstruments.isEmpty
                    )
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("settings.tradingAnalytics.instruments")
                .tradingRulesSettingsRow()
                settingsInlineDivider()
                dropdownRow(
                    "Allowed trading days",
                    info: .allowedTradingDays,
                    value: allowedDaysSummary,
                    isPlaceholder: viewModel.preferences.allowedTradingDays.isEmpty,
                    identifier: "settings.tradingAnalytics.allowedDays"
                ) {
                    ForEach(TradingRuleWeekday.displayOrder, id: \.self) { day in
                        Button {
                            viewModel.toggleAllowedDay(day)
                        } label: {
                            if viewModel.preferences.allowedTradingDays.contains(day.rawValue) {
                                Label(day.displayLabel, systemImage: "checkmark")
                            } else {
                                Text(day.displayLabel)
                            }
                        }
                    }
                }
                settingsInlineDivider()
                HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                    timeField("Planned start", info: .plannedStart, text: $viewModel.startTime, field: .startTime)
                    timeField("Planned end", info: .plannedEnd, text: $viewModel.endTime, field: .endTime)
                }
                .tradingRulesSettingsRow()
            }
        }
    }

    @ViewBuilder
    private var accountOverridesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountOverrideHeader
            if accountOverridesExpanded {
                settingsInlineDivider()
                Text("Overrides replace global limits for the selected account only.")
                    .font(.caption)
                    .foregroundStyle(colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tradingRulesSettingsRow()
                if viewModel.accounts.isEmpty {
                Text("Add a trading account to set account-specific limits.")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tradingRulesSettingsRow()
            } else {
                dropdownRow(
                    "Account",
                    info: .accountPicker,
                    value: selectedAccountName,
                    isPlaceholder: viewModel.selectedAccountID == nil,
                    identifier: "settings.tradingAnalytics.account"
                ) {
                    ForEach(viewModel.accounts) { account in
                        Button {
                            viewModel.selectAccount(account.id)
                        } label: {
                            if viewModel.selectedAccountID == account.id {
                                Label(account.name, systemImage: "checkmark")
                            } else {
                                Text(account.name)
                            }
                        }
                    }
                }
                settingsInlineDivider()
                accountOverrideField(
                    "Daily loss limit",
                    info: .accountDailyLossLimit,
                    placeholder: "500",
                    text: $viewModel.accountLoss,
                    field: .accountLoss,
                    style: .propFirmAmount
                )
                settingsInlineDivider()
                accountOverrideField(
                    "Daily profit target",
                    info: .accountDailyProfitTarget,
                    placeholder: "1000",
                    text: $viewModel.accountProfit,
                    field: .accountProfit,
                    style: .propFirmAmount
                )
                settingsInlineDivider()
                accountOverrideField(
                    TradingRulesFieldInfo.accountMaxDrawdownGoal.title,
                    info: .accountMaxDrawdownGoal,
                    placeholder: "2000",
                    text: $viewModel.accountDrawdown,
                    field: .accountDrawdown,
                    style: .propFirmAmount
                )
                }
            }
        }
    }

    private var accountOverrideHeader: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    accountOverridesExpanded.toggle()
                }
            } label: {
                HStack(spacing: ExperienceSpacing.xs) {
                    Text("Account overrides")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    Image(systemName: accountOverridesExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                "Account overrides, \(accountOverridesExpanded ? "expanded" : "collapsed")"
            )

            if viewModel.accountsWithConfiguredOverridesCount() > 0 {
                Text("\(viewModel.accountsWithConfiguredOverridesCount()) accounts")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(colors.secondaryText)
            }

            Spacer(minLength: ExperienceSpacing.xs)

            Menu {
                Button("Daily loss limit") { viewModel.clearAccountDailyLossDraft() }
                Button("Daily profit target") { viewModel.clearAccountProfitDraft() }
                Button(TradingRulesFieldInfo.accountMaxDrawdownGoal.title) { viewModel.clearAccountDrawdownDraft() }
                Divider()
                Button("Reset selected account") { viewModel.resetSelectedAccountOverrides() }
            } label: {
                Text("Reset")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.accent)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("settings.tradingAnalytics.accounts.reset")
        }
        .tradingRulesSettingsRow()
    }

    private func settingsInlineDivider() -> some View {
        ExperienceDivider()
            .padding(.leading, ExperienceSpacing.md)
    }

    @ToolbarContentBuilder
    private var tradingRulesToolbar: some ToolbarContent {
        if viewModel.hasUnsavedChanges {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsUnsavedDialog = true
                } label: {
                    HStack(spacing: ExperienceSpacing.xxs) {
                        Image(systemName: "chevron.backward")
                            .fontWeight(.semibold)
                        Text("Back")
                    }
                }
                .accessibilityIdentifier("settings.tradingAnalytics.back")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(viewModel.isSaving ? "Saving…" : "Save") {
                Task { await saveAndStay() }
            }
            .fontWeight(.semibold)
            .disabled(!viewModel.hasUnsavedChanges || viewModel.isSaving || viewModel.isLoading)
            .accessibilityIdentifier("settings.tradingAnalytics.save")
        }
    }

    private var templateDialogBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingTemplate != nil },
            set: { isPresented in
                if !isPresented { viewModel.pendingTemplate = nil }
            }
        )
    }

    @ViewBuilder
    private var templateDialogMessage: some View {
        if let template = viewModel.pendingTemplate {
            Text("\(template.label): \(template.detail) Review fields before saving.")
        }
    }

    private var templateDropdownRow: some View {
        inlineDropdownRow(
            "Rule template",
            info: .ruleTemplate,
            value: "Choose template…",
            isPlaceholder: true,
            identifier: "settings.tradingAnalytics.template"
        ) {
            ForEach(TradingRuleTemplateID.allCases.filter { $0 != .custom }) { template in
                Button {
                    viewModel.stageTemplate(template)
                } label: {
                    Text(template.label)
                }
            }
        }
    }

    private func saveAndStay() async {
        guard await viewModel.saveAll() else { return }
    }

    private func saveAndExit() async {
        guard await viewModel.saveAll() else { return }
        dismiss()
    }

    private var sessionSummary: String {
        let selected = viewModel.preferences.preferredSessions
        if selected.isEmpty { return "None" }
        return selected.map { TradingSessionCatalog.displayTitle(for: $0) }.joined(separator: ", ")
    }

    private var instrumentSummary: String {
        let symbols = viewModel.preferences.primaryInstruments
        if symbols.isEmpty { return "None" }
        return symbols.joined(separator: ", ")
    }

    private var allowedDaysSummary: String {
        let selected = TradingPreferenceRules.normalizeAllowedTradingDays(viewModel.preferences.allowedTradingDays)
        if selected.isEmpty { return "None" }
        return selected.map(\.displayLabel).joined(separator: ", ")
    }

    private var selectedAccountName: String {
        viewModel.accounts.first { $0.id == viewModel.selectedAccountID }?.name ?? "None"
    }

    private func inlineDropdownRow<MenuContent: View>(
        _ title: String,
        info: TradingRulesFieldInfo,
        value: String,
        isPlaceholder: Bool,
        identifier: String,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            TradingRulesFieldLabel(title: title, info: info)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu(content: menu) {
                dropdownValueLabel(value: value, isPlaceholder: isPlaceholder)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier(identifier)
        }
        .tradingRulesSettingsRow()
    }

    private func dropdownRow<MenuContent: View>(
        _ title: String,
        info: TradingRulesFieldInfo?,
        value: String,
        isPlaceholder: Bool,
        identifier: String,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        Menu(content: menu) {
            dropdownLabel(title, info: info, value: value, isPlaceholder: isPlaceholder)
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier(identifier)
        .tradingRulesSettingsRow()
    }

    private func dropdownValueLabel(value: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: ExperienceSpacing.xxs) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(isPlaceholder ? colors.tertiaryText : colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colors.accent)
        }
        .frame(width: TradingPreferenceFormLayout.valueColumnWidth, alignment: .trailing)
        .tradingRulesInsetControl()
    }

    private func dropdownLabel(_ title: String, info: TradingRulesFieldInfo?, value: String, isPlaceholder: Bool) -> some View {
        VStack(alignment: .leading, spacing: TradingPreferenceFormLayout.fieldStackSpacing) {
            if let info {
                TradingRulesFieldLabel(title: title, info: info)
            } else {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(colors.primaryText)
            }
            HStack(spacing: ExperienceSpacing.xs) {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(isPlaceholder ? colors.tertiaryText : colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tradingRulesInsetControl()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func numericField(
        _ title: String,
        info: TradingRulesFieldInfo,
        placeholder: String,
        text: Binding<String>,
        field: TradingAnalyticsPreferencesViewModel.DraftField,
        style: NumericInputStyle,
        keyboard: UIKeyboardType = .decimalPad
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            TradingRulesFieldLabel(title: title, info: info)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(placeholder, text: text.numericInput(style))
                .font(.subheadline)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .frame(width: TradingPreferenceFormLayout.valueColumnWidth)
                .tradingRulesInsetControl()
        }
        .tradingRulesSettingsRow()
    }

    private func accountOverrideField(
        _ title: String,
        info: TradingRulesFieldInfo,
        placeholder: String,
        text: Binding<String>,
        field: TradingAnalyticsPreferencesViewModel.DraftField,
        style: NumericInputStyle,
        keyboard: UIKeyboardType = .decimalPad
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            VStack(alignment: .leading, spacing: TradingPreferenceFormLayout.secondaryLineSpacing) {
                tradingRulesTitleInfoRow(title: title, info: info)
                Text("Override")
                    .font(.caption)
                    .foregroundStyle(colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField(placeholder, text: text.numericInput(style))
                .font(.subheadline)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .frame(width: TradingPreferenceFormLayout.valueColumnWidth)
                .tradingRulesInsetControl()
        }
        .tradingRulesSettingsRow()
    }

    private func scopedNumericField(
        _ title: String,
        info: TradingRulesFieldInfo,
        placeholder: String,
        text: Binding<String>,
        field: TradingAnalyticsPreferencesViewModel.DraftField,
        style: NumericInputStyle,
        keyboard: UIKeyboardType = .decimalPad,
        scope: Binding<TradingRuleScope>,
        scopeIdentifier: String
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            VStack(alignment: .leading, spacing: TradingPreferenceFormLayout.secondaryLineSpacing) {
                tradingRulesTitleInfoRow(title: title, info: info)
                scopeMenuCompact(selection: scope, identifier: scopeIdentifier)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField(placeholder, text: text.numericInput(style))
                .font(.subheadline)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .frame(width: TradingPreferenceFormLayout.valueColumnWidth)
                .tradingRulesInsetControl()
        }
        .tradingRulesSettingsRow()
    }

    private func tradingRulesTitleInfoRow(title: String, info: TradingRulesFieldInfo) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
            TradingRulesFieldInfoButton(info: info)
            Spacer(minLength: 0)
        }
    }

    private func scopeMenuCompact(
        selection: Binding<TradingRuleScope>,
        identifier: String
    ) -> some View {
        let label = TradingRuleScope.scopeOptions.first { $0.id == selection.wrappedValue }?.label ?? "All Accounts Combined"
        return Menu {
            ForEach(TradingRuleScope.scopeOptions, id: \.id) { option in
                Button {
                    selection.wrappedValue = option.id
                } label: {
                    if selection.wrappedValue == option.id {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Applies to, \(label)")
        .accessibilityIdentifier(identifier)
    }

    private func timeField(
        _ title: String,
        info: TradingRulesFieldInfo,
        text: Binding<String>,
        field: TradingAnalyticsPreferencesViewModel.DraftField
    ) -> some View {
        VStack(alignment: .leading, spacing: TradingPreferenceFormLayout.fieldStackSpacing) {
            tradingRulesTitleInfoRow(title: title, info: info)
            TextField("09:30", text: text)
                .font(.subheadline)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: field)
                .frame(maxWidth: .infinity)
                .tradingRulesInsetControl()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum TradingPreferenceFormLayout {
    static let fieldStackSpacing: CGFloat = ExperienceSpacing.xs
    static let secondaryLineSpacing: CGFloat = 3
    static let valueColumnWidth: CGFloat = 120
}

private extension View {
    func tradingRulesSettingsRow() -> some View {
        padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.xs + 2)
    }
}

private struct TradingPreferenceInstrumentPicker: View {
    @Bindable var viewModel: TradingAnalyticsPreferencesViewModel
    var onClose: () -> Void

    @State private var searchText = ""
    @State private var customText = ""
    @Environment(\.themeColors) private var colors

    private var filtered: InstrumentPickerSnapshot {
        viewModel.instrumentSnapshot.filtering(matching: searchText)
    }

    private var selectedSymbols: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let symbols = viewModel.preferences.primaryInstruments
        guard !query.isEmpty else { return symbols }
        return symbols.filter { $0.uppercased().contains(query) }
    }

    var body: some View {
        List {
            if !selectedSymbols.isEmpty {
                symbolSection("Selected", symbols: selectedSymbols)
            }
            symbolSection("Recent / Most Used", symbols: filtered.mostUsed)
            symbolSection("Custom", symbols: filtered.custom)
            symbolSection("Futures", symbols: filtered.futures)
            symbolSection("Stocks", symbols: filtered.stocks)
            symbolSection("Options", symbols: filtered.options)
            symbolSection("Crypto", symbols: filtered.crypto)
            symbolSection("Forex", symbols: filtered.forex)

            Section {
                TextField("Symbol", text: $customText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Add") {
                    let draft = customText
                    let before = viewModel.preferences.primaryInstruments
                    viewModel.addInstrument(draft)
                    if viewModel.preferences.primaryInstruments != before {
                        customText = ""
                    }
                }
                .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let message = viewModel.message, message.localizedCaseInsensitiveContains("symbol") {
                    Text(message)
                        .experienceStyle(.caption, color: colors.loss)
                }
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .searchable(text: $searchText, prompt: "Search instruments")
        .experienceNavigationTitle("Primary Instruments")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onClose)
            }
        }
        .onAppear { viewModel.refreshInstrumentSnapshot() }
        .accessibilityIdentifier("settings.tradingAnalytics.instrumentPicker")
    }

    @ViewBuilder
    private func symbolSection(_ title: String, symbols: [String]) -> some View {
        if !symbols.isEmpty {
            Section(title) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        viewModel.toggleInstrument(symbol)
                    } label: {
                        HStack {
                            Text(symbol)
                                .experienceStyle(.body, color: colors.primaryText)
                            Spacer()
                            if viewModel.preferences.primaryInstruments.contains(symbol) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .buttonStyle(.experiencePlain)
                }
            }
        }
    }
}
