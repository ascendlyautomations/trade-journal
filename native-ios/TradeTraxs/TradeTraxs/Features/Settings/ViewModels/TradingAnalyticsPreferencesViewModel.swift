import Foundation
import Observation

@Observable
@MainActor
final class TradingAnalyticsPreferencesViewModel {
    enum DraftField: Hashable {
        case targetRr
        case maxTrades
        case dailyLoss
        case lossPause
        case breakeven
        case profitTarget
        case drawdownGoal
        case waitMinutes
        case startTime
        case endTime
        case accountLoss
        case accountProfit
        case accountDrawdown
        case minAcceptableRr
        case maxRisk
        case maxContracts
        case maxWeeklyLoss
        case complianceGoal
    }

    private let repository: any TradingPreferencesRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let loadAccounts: (ProfileID) async throws -> [TradingAccount]

    private var savedPreferences = TradingPreferenceGlobal.empty(userID: ProfileID(""))
    private var savedOverrides: [TradingPreferenceAccountOverride] = []

    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var message: String?
    private(set) var preferences = TradingPreferenceGlobal.empty(userID: ProfileID(""))
    private(set) var overrides: [TradingPreferenceAccountOverride] = []
    private(set) var accounts: [TradingAccount] = []
    private(set) var instrumentSnapshot = InstrumentPickerSnapshot.empty
    var selectedAccountID: TradingAccountID?
    var instrumentDraft = ""

    var targetRr = ""
    var maxTrades = ""
    var dailyLoss = ""
    var lossPause = ""
    var breakeven = ""
    var profitTarget = ""
    var drawdownGoal = ""
    var waitMinutes = ""
    var complianceGoal = ""
    var startTime = ""
    var endTime = ""
    var accountLoss = ""
    var accountProfit = ""
    var accountDrawdown = ""
    var minAcceptableRr = ""
    var maxRisk = ""
    var maxContracts = ""
    var maxWeeklyLoss = ""

    var maxTradesPerDayScope: TradingRuleScope {
        get { preferences.maxTradesPerDayScope }
        set { preferences.maxTradesPerDayScope = newValue }
    }

    var dailyLossLimitScope: TradingRuleScope {
        get { preferences.dailyLossLimitScope }
        set { preferences.dailyLossLimitScope = newValue }
    }

    var dailyProfitRulesScope: TradingRuleScope {
        get { preferences.dailyProfitRulesScope }
        set { preferences.dailyProfitRulesScope = newValue }
    }

    var maxWeeklyLossScope: TradingRuleScope {
        get { preferences.maxWeeklyLossScope }
        set { preferences.maxWeeklyLossScope = newValue }
    }

    var stopAfterDailyProfitTarget: Bool {
        get { preferences.stopAfterDailyProfitTarget }
        set { preferences.stopAfterDailyProfitTarget = newValue }
    }

    var applyRulesToPastTrades: Bool {
        get { preferences.applyRulesToPastTrades }
        set { preferences.applyRulesToPastTrades = newValue }
    }

    init(
        repository: any TradingPreferencesRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        loadAccounts: @escaping (ProfileID) async throws -> [TradingAccount]
    ) {
        self.repository = repository
        self.session = session
        self.detailCache = detailCache
        self.loadAccounts = loadAccounts
    }

    var hasUnsavedChanges: Bool {
        guard !isLoading, !preferences.userID.rawValue.isEmpty else { return false }
        if preferenceChoicesDirty { return true }
        if globalTextDraftsDirty { return true }
        return accountOverridesDirty
    }

    var selectedOverride: TradingPreferenceAccountOverride? {
        guard let userID = preferences.userID.rawValue.isEmpty ? nil : preferences.userID,
              let selectedAccountID
        else { return nil }
        return overrides.first { $0.accountID == selectedAccountID }
            ?? .empty(userID: userID, accountID: selectedAccountID)
    }

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, hasUnsavedChanges {
            return
        }
        isLoading = true
        message = nil
        defer { isLoading = false }
        guard let signedIn = await session.currentUserID else {
            message = "Sign in to edit trading preferences."
            return
        }
        let userID = ProfileID(signedIn.rawValue)
        do {
            async let prefs = repository.globalPreferences(for: userID)
            async let loadedOverrides = repository.accountOverrides(for: userID)
            async let loadedAccounts = loadAccounts(userID)
            let resolvedPrefs = try await prefs
            let resolvedOverrides = try await loadedOverrides
            preferences = resolvedPrefs
            savedPreferences = resolvedPrefs
            overrides = resolvedOverrides
            savedOverrides = resolvedOverrides
            accounts = try await loadedAccounts
            if selectedAccountID == nil {
                selectedAccountID = accounts.first?.id
            }
            seedDrafts()
        } catch {
            message = TradingPreferenceSaveMessages.loadMessage(for: error)
        }
    }

    func discardChanges() {
        preferences = savedPreferences
        overrides = savedOverrides
        message = nil
        seedDrafts()
    }

    func saveAll() async -> Bool {
        guard !isSaving, !isLoading, !preferences.userID.rawValue.isEmpty else { return false }
        guard applyNumbers() else { return false }
        guard applyPlannedHours() else { return false }
        guard validateProfitStopRule() else { return false }
        stashSelectedAccountOverrideDraft()
        guard validatePendingAccountOverrides() else { return false }

        isSaving = true
        message = nil
        defer { isSaving = false }

        do {
            let persistedGlobal = try await repository.saveGlobal(preferences)
            preferences = persistedGlobal
            savedPreferences = persistedGlobal

            let pendingOverrides = overridesToPersist()
            var savedAnyOverride = false
            for pending in pendingOverrides {
                do {
                    let persisted = try await repository.saveOverride(pending)
                    savedAnyOverride = true
                    overrides.removeAll { $0.accountID == persisted.accountID }
                    overrides.append(persisted)
                    savedOverrides.removeAll { $0.accountID == persisted.accountID }
                    savedOverrides.append(persisted)
                } catch {
                    let accountLabel = accounts.first { $0.id == pending.accountID }?.name
                    message = TradingPreferenceSaveMessages.message(
                        for: error,
                        phase: .accountOverrides,
                        accountLabel: accountLabel
                    )
                    if !pendingOverrides.isEmpty, savedAnyOverride || pendingOverrides.count > 1 {
                        seedDrafts()
                    }
                    return false
                }
            }

            seedDrafts()
            TradingPreferenceDiscoveryStore.shared.bind(userID: preferences.userID, repository: repository)
            await TradingPreferenceDiscoveryStore.shared.record(.completed)
            TradingRulesCompliancePreferencesCache.invalidate(profileID: preferences.userID)
            TradingRulesComplianceRecomputeCoordinator.reset()
            NotificationCenter.default.post(name: .tradingPreferencesDidChange, object: nil)
            message = nil
            return true
        } catch {
            message = TradingPreferenceSaveMessages.message(for: error, phase: .globalRules)
            return false
        }
    }

    func selectStyle(_ style: TradingStyleID) {
        guard preferences.tradingStyle != style else { return }
        preferences.tradingStyle = style
    }

    func clearStyle() {
        guard preferences.tradingStyle != nil else { return }
        preferences.tradingStyle = nil
    }

    func clearSessions() {
        guard !preferences.preferredSessions.isEmpty else { return }
        preferences.preferredSessions = []
    }

    func clearInstruments() {
        guard !preferences.primaryInstruments.isEmpty else { return }
        preferences.primaryInstruments = []
        instrumentDraft = ""
    }

    func resetTradingPreferences() {
        guard preferences.tradingStyle != nil
            || !preferences.preferredSessions.isEmpty
            || !preferences.primaryInstruments.isEmpty
            || !preferences.allowedTradingDays.isEmpty
        else { return }
        preferences.tradingStyle = nil
        preferences.preferredSessions = []
        preferences.primaryInstruments = []
        preferences.allowedTradingDays = []
        instrumentDraft = ""
    }

    var pendingTemplate: TradingRuleTemplateID?

    func stageTemplate(_ template: TradingRuleTemplateID) {
        pendingTemplate = template
    }

  func applyStagedTemplate() {
        guard let template = pendingTemplate else { return }
        defer { pendingTemplate = nil }
        guard template != .custom, let suggested = TradingRuleTemplates.suggestedGlobal(for: template) else { return }
        if let style = suggested.tradingStyle { preferences.tradingStyle = style }
        if !suggested.preferredSessions.isEmpty { preferences.preferredSessions = suggested.preferredSessions }
        if !suggested.primaryInstruments.isEmpty { preferences.primaryInstruments = suggested.primaryInstruments }
        if let targetRr = suggested.targetRr { preferences.targetRr = targetRr }
        if let maxTradesPerDay = suggested.maxTradesPerDay { preferences.maxTradesPerDay = maxTradesPerDay }
        if let dailyLossLimit = suggested.dailyLossLimit { preferences.dailyLossLimit = dailyLossLimit }
        if let dailyProfitTarget = suggested.dailyProfitTarget { preferences.dailyProfitTarget = dailyProfitTarget }
        preferences.stopAfterDailyProfitTarget = suggested.stopAfterDailyProfitTarget
        if let maxWeeklyLoss = suggested.maxWeeklyLoss { preferences.maxWeeklyLoss = maxWeeklyLoss }
        if let maxRiskPerTrade = suggested.maxRiskPerTrade { preferences.maxRiskPerTrade = maxRiskPerTrade }
        if let minAcceptableRr = suggested.minAcceptableRr { preferences.minAcceptableRr = minAcceptableRr }
        if let maxContractsPerTrade = suggested.maxContractsPerTrade { preferences.maxContractsPerTrade = maxContractsPerTrade }
        if !suggested.allowedTradingDays.isEmpty { preferences.allowedTradingDays = suggested.allowedTradingDays }
        if let start = suggested.plannedStartMinute { preferences.plannedStartMinute = start }
        if let end = suggested.plannedEndMinute { preferences.plannedEndMinute = end }
        preferences.maxTradesPerDayScope = suggested.maxTradesPerDayScope
        preferences.dailyLossLimitScope = suggested.dailyLossLimitScope
        preferences.dailyProfitRulesScope = suggested.dailyProfitRulesScope
        preferences.maxWeeklyLossScope = suggested.maxWeeklyLossScope
        seedDrafts()
        refreshInstrumentSnapshot()
    }

    func resetTradingRules() {
        guard tradingRulesSectionDirty else { return }
        preferences.targetRr = nil
        preferences.maxTradesPerDay = nil
        preferences.dailyLossLimit = nil
        preferences.consecutiveLossPause = nil
        preferences.breakevenTolerance = nil
        preferences.minAcceptableRr = nil
        preferences.maxRiskPerTrade = nil
        preferences.maxContractsPerTrade = nil
        preferences.maxTradesPerDayScope = .combined
        preferences.dailyLossLimitScope = .combined
        seedDrafts()
    }

    func resetAdvancedRules() {
        guard advancedRulesSectionDirty else { return }
        preferences.dailyProfitTarget = nil
        preferences.maxDrawdownGoal = nil
        preferences.waitAfterLossMinutes = nil
        preferences.plannedStartMinute = nil
        preferences.plannedEndMinute = nil
        preferences.maxWeeklyLoss = nil
        preferences.stopAfterDailyProfitTarget = false
        preferences.dailyProfitRulesScope = .combined
        preferences.maxWeeklyLossScope = .combined
        seedDrafts()
    }

    func clearAllowedDays() {
        guard !preferences.allowedTradingDays.isEmpty else { return }
        preferences.allowedTradingDays = []
    }

    func toggleAllowedDay(_ day: TradingRuleWeekday) {
        var next = preferences.allowedTradingDays
        if next.contains(day.rawValue) {
            next.removeAll { $0 == day.rawValue }
        } else {
            next.append(day.rawValue)
        }
        preferences.allowedTradingDays = TradingPreferenceRules
            .normalizeAllowedTradingDays(next)
            .map(\.rawValue)
    }

    func resetSelectedAccountOverrides() {
        guard selectedAccountID != nil else { return }
        accountLoss = ""
        accountProfit = ""
        accountDrawdown = ""
        stashSelectedAccountOverrideDraft()
    }

    func clearAccountDailyLossDraft() {
        accountLoss = ""
    }

    func clearAccountProfitDraft() {
        accountProfit = ""
    }

    func clearAccountDrawdownDraft() {
        accountDrawdown = ""
    }

    func toggleSession(_ session: String) {
        if preferences.preferredSessions.contains(session) {
            preferences.preferredSessions.removeAll { $0 == session }
        } else {
            preferences.preferredSessions.append(session)
        }
        preferences.preferredSessions = TradingPreferenceRules.normalizeSessions(preferences.preferredSessions)
    }

    func addInstrument(_ raw: String? = nil) {
        let draft = raw ?? instrumentDraft
        let next = TradingPreferenceRules.normalizeInstruments(
            preferences.primaryInstruments + [draft]
        )
        guard next != preferences.primaryInstruments else {
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message = "Use 1–16 letters, numbers, or . / - for a symbol."
            }
            return
        }
        preferences.primaryInstruments = next
        instrumentDraft = ""
        message = nil
    }

    func removeInstrument(_ symbol: String) {
        guard preferences.primaryInstruments.contains(symbol) else { return }
        preferences.primaryInstruments.removeAll { $0 == symbol }
    }

    func toggleInstrument(_ symbol: String) {
        if preferences.primaryInstruments.contains(symbol) {
            removeInstrument(symbol)
        } else {
            addInstrument(symbol)
        }
    }

    func selectAccount(_ accountID: TradingAccountID) {
        guard selectedAccountID != accountID else { return }
        stashSelectedAccountOverrideDraft()
        selectedAccountID = accountID
        seedAccountDrafts()
    }

    func refreshInstrumentSnapshot() {
        guard !preferences.userID.rawValue.isEmpty else {
            instrumentSnapshot = InstrumentPickerSnapshot(
                mostUsed: [],
                custom: [],
                futures: InstrumentPickerCatalog.futures,
                stocks: InstrumentPickerCatalog.stocks,
                options: InstrumentPickerCatalog.options,
                crypto: InstrumentPickerCatalog.crypto,
                forex: InstrumentPickerCatalog.forex
            )
            return
        }
        instrumentSnapshot = InstrumentCatalog.pickerSnapshot(
            for: preferences.userID,
            detailCache: detailCache
        )
    }

    func reset(_ keyPath: WritableKeyPath<TradingPreferenceGlobal, Double?>) {
        preferences[keyPath: keyPath] = nil
        seedDrafts()
    }

    func reset(_ keyPath: WritableKeyPath<TradingPreferenceGlobal, Int?>) {
        preferences[keyPath: keyPath] = nil
        seedDrafts()
    }

    func resetHours() {
        guard preferences.plannedStartMinute != nil
            || preferences.plannedEndMinute != nil
            || !startTime.isEmpty
            || !endTime.isEmpty
        else { return }
        preferences.plannedStartMinute = nil
        preferences.plannedEndMinute = nil
        startTime = ""
        endTime = ""
    }

    private var preferenceChoicesDirty: Bool {
        preferences.tradingStyle != savedPreferences.tradingStyle
            || preferences.preferredSessions != savedPreferences.preferredSessions
            || preferences.primaryInstruments != savedPreferences.primaryInstruments
            || preferences.allowedTradingDays != savedPreferences.allowedTradingDays
            || preferences.stopAfterDailyProfitTarget != savedPreferences.stopAfterDailyProfitTarget
            || preferences.applyRulesToPastTrades != savedPreferences.applyRulesToPastTrades
            || preferences.maxTradesPerDayScope != savedPreferences.maxTradesPerDayScope
            || preferences.dailyLossLimitScope != savedPreferences.dailyLossLimitScope
            || preferences.dailyProfitRulesScope != savedPreferences.dailyProfitRulesScope
            || preferences.maxWeeklyLossScope != savedPreferences.maxWeeklyLossScope
    }

    private var tradingRulesSectionDirty: Bool {
        targetRr != Self.text(savedPreferences.targetRr, style: .riskReward)
            || maxTrades != Self.text(savedPreferences.maxTradesPerDay)
            || dailyLoss != Self.text(savedPreferences.dailyLossLimit, style: .propFirmAmount)
            || lossPause != Self.text(savedPreferences.consecutiveLossPause)
            || breakeven != Self.text(savedPreferences.breakevenTolerance, style: .propFirmAmount)
            || minAcceptableRr != Self.text(savedPreferences.minAcceptableRr, style: .riskReward)
            || maxRisk != Self.text(savedPreferences.maxRiskPerTrade, style: .propFirmAmount)
            || maxContracts != Self.text(savedPreferences.maxContractsPerTrade)
    }

    private var advancedRulesSectionDirty: Bool {
        profitTarget != Self.text(savedPreferences.dailyProfitTarget, style: .propFirmAmount)
            || drawdownGoal != Self.text(savedPreferences.maxDrawdownGoal, style: .propFirmAmount)
            || waitMinutes != Self.text(savedPreferences.waitAfterLossMinutes)
            || startTime != Self.clock(savedPreferences.plannedStartMinute)
            || endTime != Self.clock(savedPreferences.plannedEndMinute)
            || maxWeeklyLoss != Self.text(savedPreferences.maxWeeklyLoss, style: .propFirmAmount)
            || complianceGoal != Self.complianceGoalText(savedPreferences.personalComplianceTargetPercent)
    }

    private var globalTextDraftsDirty: Bool {
        tradingRulesSectionDirty || advancedRulesSectionDirty
    }

    private var accountOverridesDirty: Bool {
        if selectedAccountFieldStringsDirty { return true }
        let pendingIDs = Set(
            savedOverrides.map(\.accountID)
                + overrides.map(\.accountID)
                + (selectedAccountID.map { [$0] } ?? [])
        )
        for accountID in pendingIDs {
            let pending = mergedOverride(for: accountID)
            let saved = savedOverrides.first { $0.accountID == accountID }
                ?? .empty(userID: preferences.userID, accountID: accountID)
            if pending != saved { return true }
        }
        return false
    }

    private var selectedAccountFieldStringsDirty: Bool {
        guard let accountID = selectedAccountID else { return false }
        let saved = savedOverrides.first { $0.accountID == accountID }
        return accountLoss != Self.text(saved?.dailyLossLimit, style: .propFirmAmount)
            || accountProfit != Self.text(saved?.dailyProfitTarget, style: .propFirmAmount)
            || accountDrawdown != Self.text(saved?.maxDrawdownGoal, style: .propFirmAmount)
    }

    private func stashSelectedAccountOverrideDraft() {
        guard let accountID = selectedAccountID,
              !preferences.userID.rawValue.isEmpty
        else { return }
        let pending = buildOverrideFromAccountFields(accountID: accountID)
        overrides.removeAll { $0.accountID == accountID }
        let saved = savedOverrides.first { $0.accountID == accountID }
            ?? .empty(userID: preferences.userID, accountID: accountID)
        if pending != saved {
            overrides.append(pending)
        }
    }

    private func mergedOverride(for accountID: TradingAccountID) -> TradingPreferenceAccountOverride {
        if accountID == selectedAccountID {
            return buildOverrideFromAccountFields(accountID: accountID)
        }
        return overrides.first { $0.accountID == accountID }
            ?? savedOverrides.first { $0.accountID == accountID }
            ?? .empty(userID: preferences.userID, accountID: accountID)
    }

    private func buildOverrideFromAccountFields(accountID: TradingAccountID) -> TradingPreferenceAccountOverride {
        var override = overrides.first { $0.accountID == accountID }
            ?? savedOverrides.first { $0.accountID == accountID }
            ?? .empty(userID: preferences.userID, accountID: accountID)

        if accountID == selectedAccountID {
            if let amount = Self.positive(accountLoss) {
                override.overridesDailyLoss = true
                override.dailyLossLimit = amount
            } else if Self.plain(accountLoss).isEmpty {
                override.overridesDailyLoss = false
                override.dailyLossLimit = nil
            }

            if let amount = Self.positive(accountProfit) {
                override.overridesDailyProfitTarget = true
                override.dailyProfitTarget = amount
            } else if Self.plain(accountProfit).isEmpty {
                override.overridesDailyProfitTarget = false
                override.dailyProfitTarget = nil
            }

            if let amount = Self.positive(accountDrawdown) {
                override.overridesMaxDrawdownGoal = true
                override.maxDrawdownGoal = amount
            } else if Self.plain(accountDrawdown).isEmpty {
                override.overridesMaxDrawdownGoal = false
                override.maxDrawdownGoal = nil
            }
        }

        return override
    }

    private func validatePendingAccountOverrides() -> Bool {
        let accountIDs = Set(
            savedOverrides.map(\.accountID)
                + overrides.map(\.accountID)
                + (selectedAccountID.map { [$0] } ?? [])
        )
        for accountID in accountIDs {
            let pending = mergedOverride(for: accountID)
            if pending.overridesDailyLoss, pending.dailyLossLimit == nil {
                message = "Enter a dollar amount above 0 for the account daily loss limit."
                return false
            }
            if pending.overridesDailyProfitTarget, pending.dailyProfitTarget == nil {
                message = "Enter a dollar amount above 0 for the account profit target."
                return false
            }
            if pending.overridesMaxDrawdownGoal, pending.maxDrawdownGoal == nil {
                message = "Enter a dollar amount above 0 for the account drawdown goal."
                return false
            }
            if accountID == selectedAccountID {
                if !Self.plain(accountLoss).isEmpty, Self.positive(accountLoss) == nil {
                    message = "Enter a dollar amount above 0."
                    return false
                }
                if !Self.plain(accountProfit).isEmpty, Self.positive(accountProfit) == nil {
                    message = "Enter a dollar amount above 0."
                    return false
                }
                if !Self.plain(accountDrawdown).isEmpty, Self.positive(accountDrawdown) == nil {
                    message = "Enter a dollar amount above 0."
                    return false
                }
            }
        }
        message = nil
        return true
    }

    private func overridesToPersist() -> [TradingPreferenceAccountOverride] {
        let accountIDs = Set(
            savedOverrides.map(\.accountID)
                + overrides.map(\.accountID)
                + (selectedAccountID.map { [$0] } ?? [])
        )
        return accountIDs.compactMap { accountID in
            let pending = mergedOverride(for: accountID)
            let saved = savedOverrides.first { $0.accountID == accountID }
                ?? .empty(userID: preferences.userID, accountID: accountID)
            guard pending != saved else { return nil }
            return pending
        }
    }

    private func applyPlannedHours() -> Bool {
        let startBlank = startTime.trimmingCharacters(in: .whitespaces).isEmpty
        let endBlank = endTime.trimmingCharacters(in: .whitespaces).isEmpty
        if startBlank && endBlank {
            preferences.plannedStartMinute = nil
            preferences.plannedEndMinute = nil
            return true
        }
        guard let start = Self.minutes(from: startTime),
              let end = Self.minutes(from: endTime),
              start != end
        else {
            message = "Enter both an Eastern start and end, and make them different."
            return false
        }
        preferences.plannedStartMinute = start
        preferences.plannedEndMinute = end
        return true
    }

    private func applyNumbers() -> Bool {
        if let value = Self.optionalPositive(targetRr) { preferences.targetRr = value }
        else { message = "Enter a target R above 0, or leave it blank."; return false }
        if let value = Self.optionalInt(maxTrades, min: 1, max: 100) { preferences.maxTradesPerDay = value }
        else { message = "Enter a whole number of trades from 1 to 100, or leave it blank."; return false }
        if let value = Self.optionalPositive(dailyLoss) { preferences.dailyLossLimit = value }
        else { message = "Enter a daily loss amount above 0, or leave it blank."; return false }
        if let value = Self.optionalInt(lossPause, min: 1, max: 50) { preferences.consecutiveLossPause = value }
        else { message = "Enter consecutive losses from 1 to 50, or leave it blank."; return false }
        if let value = Self.optionalNonNegative(breakeven) { preferences.breakevenTolerance = value }
        else { message = "Enter a breakeven tolerance of 0 or more, or leave it blank."; return false }
        if let value = Self.optionalPositive(profitTarget) { preferences.dailyProfitTarget = value }
        else { message = "Enter a profit target above 0, or leave it blank."; return false }
        if let value = Self.optionalPositive(drawdownGoal) { preferences.maxDrawdownGoal = value }
        else { message = "Enter a drawdown goal above 0, or leave it blank."; return false }
        if let value = Self.optionalInt(waitMinutes, min: 0, max: 1440) { preferences.waitAfterLossMinutes = value }
        else { message = "Enter waiting time in whole minutes from 0 to 1440, or leave it blank."; return false }
        if let value = Self.optionalPositive(minAcceptableRr) { preferences.minAcceptableRr = value }
        else { message = "Enter a minimum R:R above 0, or leave it blank."; return false }
        if let value = Self.optionalPositive(maxRisk) { preferences.maxRiskPerTrade = value }
        else { message = "Enter a maximum risk amount above 0, or leave it blank."; return false }
        if let value = Self.optionalInt(maxContracts, min: 1, max: 10_000) { preferences.maxContractsPerTrade = value }
        else { message = "Enter whole contracts from 1 to 10,000, or leave it blank."; return false }
        if let value = Self.optionalPositive(maxWeeklyLoss) { preferences.maxWeeklyLoss = value }
        else { message = "Enter a weekly loss amount above 0, or leave it blank."; return false }
        if complianceGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferences.personalComplianceTargetPercent = nil
        } else if let parsed = Self.optionalNonNegative(complianceGoal), let value = parsed, value <= 100 {
            preferences.personalComplianceTargetPercent = value
        } else {
            message = "Enter a compliance goal from 0 to 100, or leave blank for the 90% default in analytics."
            return false
        }
        message = nil
        return true
    }

    private func validateProfitStopRule() -> Bool {
        if preferences.stopAfterDailyProfitTarget, preferences.dailyProfitTarget == nil {
            message = "Set a daily profit target before turning on stop-after-target."
            return false
        }
        message = nil
        return true
    }

    private func seedDrafts() {
        targetRr = Self.text(preferences.targetRr, style: .riskReward)
        maxTrades = Self.text(preferences.maxTradesPerDay)
        dailyLoss = Self.text(preferences.dailyLossLimit, style: .propFirmAmount)
        lossPause = Self.text(preferences.consecutiveLossPause)
        breakeven = Self.text(preferences.breakevenTolerance, style: .propFirmAmount)
        minAcceptableRr = Self.text(preferences.minAcceptableRr, style: .riskReward)
        maxRisk = Self.text(preferences.maxRiskPerTrade, style: .propFirmAmount)
        maxContracts = Self.text(preferences.maxContractsPerTrade)
        profitTarget = Self.text(preferences.dailyProfitTarget, style: .propFirmAmount)
        drawdownGoal = Self.text(preferences.maxDrawdownGoal, style: .propFirmAmount)
        maxWeeklyLoss = Self.text(preferences.maxWeeklyLoss, style: .propFirmAmount)
        waitMinutes = Self.text(preferences.waitAfterLossMinutes)
        complianceGoal = Self.complianceGoalText(preferences.personalComplianceTargetPercent)
        startTime = Self.clock(preferences.plannedStartMinute)
        endTime = Self.clock(preferences.plannedEndMinute)
        seedAccountDrafts()
    }

    private func seedAccountDrafts() {
        let override = selectedOverride
        accountLoss = Self.text(override?.dailyLossLimit, style: .propFirmAmount)
        accountProfit = Self.text(override?.dailyProfitTarget, style: .propFirmAmount)
        accountDrawdown = Self.text(override?.maxDrawdownGoal, style: .propFirmAmount)
    }

    private static func text(_ value: Double?, style: NumericInputStyle) -> String {
        guard let value else { return "" }
        let raw = value == value.rounded() ? String(Int(value)) : String(value)
        return NumericInputFieldSupport.formatWhileEditing(raw, style: style)
    }

    private static func complianceGoalText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(Int(value.rounded()))
    }

    private static func text(_ value: Int?) -> String {
        guard let value else { return "" }
        return NumericInputFieldSupport.formatWhileEditing(String(value), style: .unsignedInteger)
    }

    private static func clock(_ minutes: Int?) -> String {
        guard let minutes else { return "" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func plain(_ raw: String) -> String {
        NumericInputFieldSupport.plainNumericString(from: raw)
    }

    private static func optionalPositive(_ raw: String) -> Double?? {
        let trimmed = plain(raw)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), value > 0 else { return nil }
        return .some(value)
    }

    private static func optionalNonNegative(_ raw: String) -> Double?? {
        let trimmed = plain(raw)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return .some(value)
    }

    private static func positive(_ raw: String) -> Double? {
        let trimmed = plain(raw)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    private static func optionalInt(_ raw: String, min: Int, max: Int) -> Int?? {
        let trimmed = plain(raw)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Int(trimmed), value >= min, value <= max else { return nil }
        return .some(value)
    }

    private static func minutes(from raw: String) -> Int? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              hour >= 0, hour < 24, minute >= 0, minute < 60
        else { return nil }
        return hour * 60 + minute
    }
}

extension TradingAnalyticsPreferencesViewModel {
    enum SettingsCategory: String, CaseIterable, Identifiable {
        case general = "General Settings"
        case riskManagement = "Risk Management"
        case tradeExecution = "Trade Execution"
        case discipline = "Discipline"
        case sessionsAndInstruments = "Sessions & Instruments"

        var id: String { rawValue }
    }

    func configuredRuleCount(for category: SettingsCategory) -> Int {
        switch category {
        case .general:
            var count = 0
            if applyRulesToPastTrades { count += 1 }
            if draftConfigured(complianceGoal) { count += 1 }
            return count
        case .riskManagement:
            var count = 0
            if draftConfigured(dailyLoss) { count += 1 }
            if draftConfigured(maxRisk) { count += 1 }
            if draftConfigured(breakeven) { count += 1 }
            if draftConfigured(maxWeeklyLoss) { count += 1 }
            if draftConfigured(drawdownGoal) { count += 1 }
            count += accountsWithConfiguredOverridesCount()
            return count
        case .tradeExecution:
            var count = 0
            if draftConfigured(targetRr) { count += 1 }
            if draftConfigured(minAcceptableRr) { count += 1 }
            if draftConfigured(maxContracts) { count += 1 }
            if draftConfigured(maxTrades) { count += 1 }
            return count
        case .discipline:
            var count = 0
            if draftConfigured(lossPause) { count += 1 }
            if draftConfigured(waitMinutes) { count += 1 }
            if draftConfigured(profitTarget) { count += 1 }
            if stopAfterDailyProfitTarget { count += 1 }
            return count
        case .sessionsAndInstruments:
            var count = 0
            if !preferences.preferredSessions.isEmpty { count += 1 }
            if !preferences.primaryInstruments.isEmpty { count += 1 }
            if !TradingPreferenceRules.normalizeAllowedTradingDays(preferences.allowedTradingDays).isEmpty {
                count += 1
            }
            if draftConfigured(startTime) || draftConfigured(endTime) { count += 1 }
            return count
        }
    }

    func accountsWithConfiguredOverridesCount() -> Int {
        let accountIDs = Set(
            accounts.map(\.id)
                + savedOverrides.map(\.accountID)
                + overrides.map(\.accountID)
        )
        return accountIDs.filter { hasConfiguredOverride(for: $0) }.count
    }

    private func hasConfiguredOverride(for accountID: TradingAccountID) -> Bool {
        let override = effectiveOverrideForDisplay(accountID: accountID)
        return override.dailyLossLimit != nil
            || override.dailyProfitTarget != nil
            || override.maxDrawdownGoal != nil
    }

    private func effectiveOverrideForDisplay(accountID: TradingAccountID) -> TradingPreferenceAccountOverride {
        if accountID == selectedAccountID {
            return buildOverrideFromAccountFields(accountID: accountID)
        }
        return overrides.first { $0.accountID == accountID }
            ?? savedOverrides.first { $0.accountID == accountID }
            ?? .empty(userID: preferences.userID, accountID: accountID)
    }

    private func draftConfigured(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
