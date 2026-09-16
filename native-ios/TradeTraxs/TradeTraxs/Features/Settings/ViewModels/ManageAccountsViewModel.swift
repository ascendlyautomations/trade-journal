import Foundation
import Observation

@Observable
@MainActor
final class ManageAccountsViewModel {
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache

    private(set) var accounts: [TradingAccount] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var formError: String?
    private var hasLoaded = false
    private var viewerID: ProfileID?
    private(set) var isLoadingPayouts = false
    private(set) var payoutError: String?

    var propFirmFilter: ManageAccountsFiltering.PropFirmFilter = .all
    var modeFilter: ManageAccountsFiltering.ModeFilter = .all
    var sort: ManageAccountsFiltering.Sort = .accountName

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
    }

    var filteredAccounts: [TradingAccount] {
        ManageAccountsFiltering.apply(
            to: accounts,
            propFirm: propFirmFilter,
            mode: modeFilter,
            sort: sort
        )
    }

    var availablePropFirms: [String] {
        ManageAccountsFiltering.availablePropFirms(from: accounts)
    }

    var availableModes: [TradingAccountMode] {
        ManageAccountsFiltering.availableModes(from: accounts)
    }

    var hasActiveFilters: Bool {
        ManageAccountsFiltering.hasActiveFilters(propFirm: propFirmFilter, mode: modeFilter)
    }

    var showsFilteredEmptyState: Bool {
        !accounts.isEmpty && filteredAccounts.isEmpty && hasActiveFilters
    }

    func setPropFirmFilter(_ filter: ManageAccountsFiltering.PropFirmFilter) {
        guard propFirmFilter != filter else { return }
        propFirmFilter = filter
        ExperienceHaptics.play(.selection)
    }

    func setModeFilter(_ filter: ManageAccountsFiltering.ModeFilter) {
        guard modeFilter != filter else { return }
        modeFilter = filter
        ExperienceHaptics.play(.selection)
    }

    func setSort(_ sort: ManageAccountsFiltering.Sort) {
        guard self.sort != sort else { return }
        self.sort = sort
        ExperienceHaptics.play(.selection)
    }

    func clearFilters() {
        propFirmFilter = .all
        modeFilter = .all
        ExperienceHaptics.play(.selection)
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await loadAccounts(requiresFullOwnerSnapshot: true) }
    }

    /// Cache-first accounts for Withdrawals — awaits load; never exits while accounts are still loading.
    func ensureAccountsReadyForWithdrawals() async {
        WithdrawalsTrace.log("ensureAccountsStarted")
        if let userID = await session.currentUserID {
            let profileID = ProfileID(userID.rawValue)
            viewerID = profileID
            WithdrawalsHistoryStore.shared.bindProfile(profileID)
            WithdrawalsHistoryStore.shared.hydrateFromSessionCaches(profileID: profileID)
            if accounts.isEmpty,
               let cached = SessionAccountsStore.shared.cached(for: profileID),
               !cached.isEmpty
            {
                accounts = Self.sorted(cached)
                WithdrawalsTrace.log("accountsResolved", detail: "source=sessionCache count=\(accounts.count)")
            }
        }
        if accounts.isEmpty {
            if !hasLoaded {
                hasLoaded = true
            }
            await loadAccounts(requiresFullOwnerSnapshot: true)
        }
        let deadline = Date().addingTimeInterval(15)
        while accounts.isEmpty, Date() < deadline {
            if isLoading {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            if errorMessage != nil {
                WithdrawalsTrace.log("earlyReturn", detail: "accountsError=\(errorMessage ?? "")")
                break
            }
            await loadAccounts(requiresFullOwnerSnapshot: true)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        WithdrawalsTrace.log(
            "accountsResolved",
            detail: "count=\(accounts.count) isLoading=\(isLoading)"
        )
    }

    func refresh() async {
        await loadAccounts(forceNetwork: true)
    }

    /// Cache-first initial open; pull-to-refresh uses ``refresh``.
    func loadAccounts(
        forceNetwork: Bool = false,
        requiresFullOwnerSnapshot: Bool = false
    ) async {
        isLoading = accounts.isEmpty
        do {
            guard let userID = await session.currentUserID else {
                errorMessage = "Sign in to continue."
                isLoading = false
                return
            }
            viewerID = ProfileID(userID.rawValue)
            WithdrawalsHistoryStore.shared.bindProfile(ProfileID(userID.rawValue))
            WithdrawalsHistoryStore.shared.hydrateFromSessionCaches(profileID: ProfileID(userID.rawValue))
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: ProfileID(userID.rawValue),
                detailCache: detailCache,
                repository: trades,
                forceNetwork: forceNetwork,
                requiresFullOwnerSnapshot: requiresFullOwnerSnapshot
            )
            accounts = Self.sorted(loaded)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    func emptyDraft() -> TradingAccountDraft {
        TradingAccountDraft(
            name: "",
            sizeDigits: "",
            accountNumber: "",
            category: .personal,
            mode: .live,
            note: "",
            propFirmRules: nil
        )
    }

    func draft(from account: TradingAccount) -> TradingAccountDraft {
        TradingAccountDraft(
            name: account.name,
            sizeDigits: account.size.map {
                NumericInputFieldSupport.seedEditingText(from: $0.amount, style: .accountSize)
            } ?? "",
            accountNumber: account.accountNumber ?? "",
            category: account.category,
            mode: account.mode,
            note: account.note ?? "",
            propFirmRules: account.propFirmRules
        )
    }

    func create(_ draft: TradingAccountDraft) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let created = try await trades.createAccount(ownerID: viewerID, draft: draft)
            accounts = Self.sorted(accounts + [created])
            SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            AccountMutationStore.shared.noteAccountCreated(created, allAccounts: accounts)
            ExperienceHaptics.play(.success)
        }
    }

    func update(id: TradingAccountID, draft: TradingAccountDraft) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let updated = try await trades.updateAccount(id: id, ownerID: viewerID, draft: draft)
            accounts = Self.sorted(accounts.map { $0.id == id ? updated : $0 })
            SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            AccountMutationStore.shared.noteAccountUpdated(updated, allAccounts: accounts)
            ExperienceHaptics.play(.success)
        }
    }

    func setActive(id: TradingAccountID, isActive: Bool) async {
        _ = await mutate {
            try await trades.setAccountActive(id: id, isActive: isActive)
            accounts = Self.sorted(accounts.map { account in
                guard account.id == id else { return account }
                var copy = account
                copy.isActive = isActive
                return copy
            })
            if let viewerID {
                SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            }
            if let updated = accounts.first(where: { $0.id == id }) {
                AccountMutationStore.shared.noteAccountUpdated(updated, allAccounts: accounts)
            }
            ExperienceHaptics.play(.selection)
        }
    }

    func setShowInAccountDropdowns(id: TradingAccountID, show: Bool) async {
        guard let account = accounts.first(where: { $0.id == id }),
              account.showInAccountDropdowns != show
        else { return }

        _ = await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let updated = try await trades.updateAccountInsightsSettings(
                id: id,
                ownerID: viewerID,
                showInAccountDropdowns: show,
                customPublicStatus: account.customPublicStatus
            )
            accounts = Self.sorted(accounts.map { $0.id == id ? updated : $0 })
            SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            AccountMutationStore.shared.noteAccountUpdated(updated, allAccounts: accounts)
            ExperienceHaptics.play(.selection)
        }
    }

    func showInAccountDropdowns(for accountID: TradingAccountID) -> Bool {
        accounts.first(where: { $0.id == accountID })?.showInAccountDropdowns ?? true
    }

    func payoutEntries(for accountID: TradingAccountID) -> [AccountPayoutEntry] {
        WithdrawalsHistoryStore.shared.ledgerByAccount[accountID] ?? []
    }

    var allPayoutEntriesByAccount: [TradingAccountID: [AccountPayoutEntry]] {
        WithdrawalsHistoryStore.shared.ledgerByAccount
    }

    func loadPayoutEntries(for accountID: TradingAccountID) async {
        isLoadingPayouts = payoutEntries(for: accountID).isEmpty
        payoutError = nil
        defer { isLoadingPayouts = false }
        do {
            let rows = try await trades.payoutEntries(for: accountID)
            if let viewerID {
                WithdrawalsHistoryStore.shared.setLedgerEntries(rows, accountID: accountID, profileID: viewerID)
            }
        } catch {
            payoutError = UserFacingError.message(for: error)
        }
    }

    func syncPayoutEntriesFromSessionStore() {
        guard let viewerID else { return }
        WithdrawalsHistoryStore.shared.hydrateFromSessionCaches(profileID: viewerID)
    }

    func loadAllPayoutEntries() async {
        if let viewerID {
            WithdrawalsHistoryStore.shared.hydrateFromSessionCaches(profileID: viewerID)
        }
        let accountIDs = accounts.map(\.id)
        guard !accountIDs.isEmpty else { return }
        isLoadingPayouts = WithdrawalsHistoryStore.shared.ledgerByAccount.isEmpty
        payoutError = nil
        defer { isLoadingPayouts = false }

        let started = CFAbsoluteTimeGetCurrent()
        WithdrawalsTrace.log("ledgerFetchStarted", detail: "accounts=\(accountIDs.count)")
        do {
            let rows = try await trades.payoutEntries(for: accountIDs)
            var grouped: [TradingAccountID: [AccountPayoutEntry]] = [:]
            for accountID in accountIDs {
                grouped[accountID] = []
            }
            for entry in rows {
                grouped[entry.accountID, default: []].append(entry)
            }
            if let viewerID {
                WithdrawalsHistoryStore.shared.applyLedgerSnapshot(grouped, profileID: viewerID)
            }
            PayoutBatchDiagnostics.logEntries(
                accounts: accountIDs.count,
                requests: 1,
                entries: rows.count,
                dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            )
            WithdrawalsTrace.log("ledgerFetchCompleted", detail: "entries=\(rows.count)")
        } catch {
            payoutError = UserFacingError.message(for: error)
            WithdrawalsTrace.log("ledgerFetchFailed", detail: UserFacingError.message(for: error))
        }
    }

    func updateInsightsSettings(
        accountID: TradingAccountID,
        showInAccountDropdowns: Bool,
        customPublicStatus: String
    ) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let trimmedStatus = customPublicStatus.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await trades.updateAccountInsightsSettings(
                id: accountID,
                ownerID: viewerID,
                showInAccountDropdowns: showInAccountDropdowns,
                customPublicStatus: trimmedStatus.isEmpty ? nil : trimmedStatus
            )
            accounts = Self.sorted(accounts.map { $0.id == accountID ? updated : $0 })
            SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            AccountMutationStore.shared.noteAccountUpdated(updated, allAccounts: accounts)
            ExperienceHaptics.play(.success)
        }
    }

    func createPayout(
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft
    ) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let created = try await trades.createPayoutEntry(
                ownerID: viewerID,
                accountID: accountID,
                draft: draft
            )
            WithdrawalsHistoryStore.shared.bindProfile(viewerID)
            WithdrawalsHistoryStore.shared.prependLedgerEntry(created, profileID: viewerID)
            AccountMutationStore.shared.notePayoutRecorded(accountID: accountID)
            ExperienceHaptics.play(.success)
        }
    }

    func updatePayout(
        entryID: AccountPayoutEntryID,
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft
    ) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let updated = try await trades.updatePayoutEntry(id: entryID, draft: draft)
            WithdrawalsHistoryStore.shared.replaceLedgerEntry(updated, profileID: viewerID)
            AccountMutationStore.shared.notePayoutRecorded(accountID: accountID)
            ExperienceHaptics.play(.success)
        }
    }

    func deletePayout(entryID: AccountPayoutEntryID, accountID: TradingAccountID) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            try await trades.deletePayoutEntry(id: entryID)
            WithdrawalsHistoryStore.shared.removeLedgerEntry(
                entryID: entryID,
                accountID: accountID,
                profileID: viewerID
            )
            AccountMutationStore.shared.notePayoutRecorded(accountID: accountID)
            ExperienceHaptics.play(.selection)
        }
    }

    func rowTitle(for account: TradingAccount) -> String {
        if let firm = TradingAccountDisplay.propFirmName(for: account) {
            return firm
        }
        let trimmed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return account.category.rawValue.capitalized
    }

    func rowSubtitle(for account: TradingAccount) -> String {
        var parts: [String] = []
        if account.isPropFirmAccount {
            let firm = TradingAccountDisplay.inferPropFirmName(account.name)
            let trimmedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty, trimmedName.compare(firm, options: .caseInsensitive) != .orderedSame {
                parts.append(trimmedName)
            }
        }
        parts.append(Self.modeLabel(account.mode, category: account.category))
        if let suffix = TradingAccountDisplay.maskedAccountNumberSuffix(account.accountNumber) {
            parts.append(suffix)
        }
        if let status = account.customPublicStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
            parts.append(status)
        }
        if !account.canAddTrades {
            parts.append("Read Only")
        }
        if !account.isActive {
            parts.append("Inactive")
        }
        return parts.joined(separator: " · ")
    }

    func subtitle(for account: TradingAccount) -> String {
        rowSubtitle(for: account)
    }

    static func modeFilterLabel(_ mode: TradingAccountMode) -> String {
        ManageAccountsFiltering.modeFilterLabel(mode)
    }

    static func modeLabel(_ mode: TradingAccountMode, category: TradingAccountCategory) -> String {
        switch category {
        case .propFirm:
            return mode == .funded ? "Funded" : "Eval"
        case .backtest:
            return "Backtest"
        case .personal, .broker:
            return mode == .sim ? "Sim" : "Live"
        }
    }

    static func modes(for category: TradingAccountCategory) -> [TradingAccountMode] {
        switch category {
        case .propFirm: return [.evaluation, .funded]
        case .backtest: return [.backtest]
        case .personal, .broker: return [.live, .sim]
        }
    }

    static func defaultMode(for category: TradingAccountCategory) -> TradingAccountMode {
        switch category {
        case .propFirm: return .evaluation
        case .backtest: return .backtest
        case .personal, .broker: return .live
        }
    }

    // MARK: - Private

    private func mutate(_ work: () async throws -> Void) async -> Bool {
        formError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await work()
            return true
        } catch {
            if let app = error as? AppError, case .unknown(let message) = app {
                formError = message
            } else {
                formError = UserFacingError.message(for: error)
            }
            return false
        }
    }

    private static func sorted(_ accounts: [TradingAccount]) -> [TradingAccount] {
        accounts.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
