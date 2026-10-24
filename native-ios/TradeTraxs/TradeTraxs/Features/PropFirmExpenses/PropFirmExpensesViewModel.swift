import Foundation
import Observation

@MainActor
@Observable
final class PropFirmExpensesViewModel {
    private(set) var expenses: [PropFirmExpense] = []
    private(set) var income: [TrackerIncome] = []
    private(set) var withdrawalItems: [PayoutHistoryItem] = []
    private(set) var accounts: [TradingAccount] = []
    private(set) var payouts: Decimal = 0
    private(set) var propPayoutItems: [PayoutHistoryItem] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var reserveError: String?
    var formError: String?
    var selectedYear: Int
    var reservePercent: Decimal = PropFirmYearOverviewBuilder.defaultPercent
    private(set) var payoutFirmNames: [String: String] = [:]
    private(set) var savedCategories: [String] = []

    private let data: DataEnvironment
    private var loadedProfileID: ProfileID?

    init(data: DataEnvironment) {
        self.data = data
        self.selectedYear = Calendar.current.component(.year, from: .now)
    }

    var analytics: PropFirmExpenseAnalytics {
        PropFirmExpenseAnalyticsBuilder.summarize(expenses: expenses, payouts: payouts)
    }

    var overview: PropFirmYearOverview {
        let accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let rows = trackerPayouts.map { item in
            PropFirmOverviewPayout(
                payoutDate: PropFirmExpenseMoney.utcDayString(from: item.date),
                accountID: item.accountID,
                amount: item.amount,
                assignedFirmName: payoutFirmNames[item.id],
                accountName: accountNames[item.accountID]
            )
        }
        return PropFirmYearOverviewBuilder.summarize(
            year: selectedYear,
            expenses: ExpenseRecurrenceSchedule.expand(
                expenses,
                through: PropFirmExpenseMoney.dayString(from: .now)
            ),
            payouts: rows,
            reservePercent: reservePercent
        )
    }

    func firmOptions() -> [(key: String, label: String)] {
        var names: [String: String] = [:]
        for expense in expenses {
            let label = expense.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = label.lowercased()
            if names[key] == nil { names[key] = label }
        }
        return names
            .map { (key: $0.key, label: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    func load(force: Bool = false) async {
        guard let userID = await data.session.currentUserID else {
            errorMessage = "Sign in to track prop firm expenses."
            return
        }
        let profileID = ProfileID(userID.rawValue)
        if !force, loadedProfileID == profileID {
            return
        }
        isLoading = expenses.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            accounts = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                repository: data.trades,
                forceNetwork: force
            )
            let repository = PropFirmExpenseRepository(supabase: data.supabase)
            async let expenseTask = repository.list(userID: profileID)
            async let incomeTask = repository.listIncome(userID: profileID)
            async let percentTask = repository.taxReservePercent(userID: profileID)
            do {
                expenses = try await expenseTask
                income = try await incomeTask
            } catch {
                reservePercent = await percentTask
                throw error
            }
            reservePercent = await percentTask
            savedCategories = await repository.categories(userID: profileID)
            if let names = try? await repository.payoutAssignments(userID: profileID) {
                PropFirmPayoutAssignmentStore.shared.replace(names)
                payoutFirmNames = names
            }
            do {
                payouts = try await loadPropPayouts(profileID: profileID, force: force)
            } catch {
                payouts = 0
                propPayoutItems = []
            }
            loadedProfileID = profileID
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func save(draft: PropFirmExpenseDraft, existing: PropFirmExpense?) async -> Bool {
        guard let userID = await data.session.currentUserID else { return false }
        let today = PropFirmExpenseMoney.dayString(from: .now)
        if let message = PropFirmExpenseAnalyticsBuilder.validate(draft, today: today) {
            formError = message
            return false
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }
        do {
            let repository = PropFirmExpenseRepository(supabase: data.supabase)
            let saved: PropFirmExpense
            if let existing {
                saved = try await repository.update(
                    userID: ProfileID(userID.rawValue),
                    expense: existing,
                    draft: draft
                )
                expenses = expenses.map { $0.id == saved.id ? saved : $0 }
            } else {
                saved = try await repository.create(userID: ProfileID(userID.rawValue), draft: draft)
                expenses.insert(saved, at: 0)
            }
            expenses.sort { lhs, rhs in
                if lhs.datePaid == rhs.datePaid { return lhs.id > rhs.id }
                return lhs.datePaid > rhs.datePaid
            }
            if draft.trackerKind != .propFirm {
                await repository.saveCategory(userID: ProfileID(userID.rawValue), name: draft.customCategory)
                if !savedCategories.contains(where: { $0.caseInsensitiveCompare(draft.customCategory) == .orderedSame }) {
                    savedCategories.append(draft.customCategory.trimmingCharacters(in: .whitespacesAndNewlines))
                    savedCategories.sort()
                }
            }
            return true
        } catch {
            formError = UserFacingError.message(for: error)
            return false
        }
    }

    func delete(_ expense: PropFirmExpense) async -> Bool {
        guard let userID = await data.session.currentUserID else { return false }
        isSaving = true
        formError = nil
        defer { isSaving = false }
        do {
            try await PropFirmExpenseRepository(supabase: data.supabase).delete(
                userID: ProfileID(userID.rawValue),
                expenseID: expense.savedID
            )
            expenses.removeAll { $0.id == expense.savedID }
            return true
        } catch {
            formError = UserFacingError.message(for: error)
            return false
        }
    }

    func saveIncome(draft: TrackerIncomeDraft, existing: TrackerIncome?) async -> Bool {
        guard let userID = await data.session.currentUserID else { return false }
        let today = PropFirmExpenseMoney.dayString(from: .now)
        if let message = TrackerIncomeDraft.validate(draft, today: today) {
            formError = message
            return false
        }
        isSaving = true
        formError = nil
        defer { isSaving = false }
        do {
            let repository = PropFirmExpenseRepository(supabase: data.supabase)
            let profileID = ProfileID(userID.rawValue)
            let saved: TrackerIncome
            if let existing {
                saved = try await repository.updateIncome(userID: profileID, incomeID: existing.savedID, draft: draft)
                income = income.map { $0.id == saved.id ? saved : $0 }
            } else {
                saved = try await repository.createIncome(userID: profileID, draft: draft)
                income.insert(saved, at: 0)
            }
            income.sort { lhs, rhs in
                if lhs.dateReceived == rhs.dateReceived { return lhs.id > rhs.id }
                return lhs.dateReceived > rhs.dateReceived
            }
            return true
        } catch {
            formError = UserFacingError.message(for: error)
            return false
        }
    }

    func deleteIncome(_ incomeRow: TrackerIncome) async -> Bool {
        guard let userID = await data.session.currentUserID else { return false }
        isSaving = true
        formError = nil
        defer { isSaving = false }
        do {
            try await PropFirmExpenseRepository(supabase: data.supabase).deleteIncome(
                userID: ProfileID(userID.rawValue),
                incomeID: incomeRow.savedID
            )
            income.removeAll { $0.id == incomeRow.savedID }
            return true
        } catch {
            formError = UserFacingError.message(for: error)
            return false
        }
    }

    private func loadPropPayouts(profileID: ProfileID, force: Bool) async throws -> Decimal {
        let accountIDs = accounts.map(\.id)
        let entries: [TradingAccountID: [AccountPayoutEntry]]
        if !force, let cached = SessionPayoutEntriesStore.shared.all(for: profileID) {
            entries = cached
        } else if accountIDs.isEmpty {
            entries = [:]
        } else {
            let rows = try await data.trades.payoutEntries(for: accountIDs)
            var grouped: [TradingAccountID: [AccountPayoutEntry]] = [:]
            for id in accountIDs { grouped[id] = [] }
            for row in rows { grouped[row.accountID, default: []].append(row) }
            WithdrawalsHistoryStore.shared.applyLedgerSnapshot(grouped, profileID: profileID)
            entries = grouped
        }

        let fundedIDs = accounts.filter { PropFirmPayoutPolicy.supportsRecordPayout(for: $0) }.map(\.id)
        var cycles: [TradingAccountID: [AccountPayoutCycle]] = [:]
        var missing: [TradingAccountID] = []
        for id in fundedIDs {
            if !force, let cached = SessionPayoutCyclesStore.shared.cached(for: id, profileID: profileID) {
                cycles[id] = cached
            } else {
                missing.append(id)
            }
        }
        if !missing.isEmpty {
            let fetched = try await data.trades.payoutCycleHistory(for: missing)
            var grouped: [TradingAccountID: [AccountPayoutCycle]] = [:]
            for id in missing { grouped[id] = [] }
            for cycle in fetched { grouped[cycle.accountID, default: []].append(cycle) }
            for (id, rows) in grouped {
                cycles[id] = rows
                SessionPayoutCyclesStore.shared.seed(rows, for: id, profileID: profileID)
            }
        }

        let history = PayoutHistorySupport.buildHistory(
            accounts: accounts,
            entriesByAccount: entries,
            cyclesByAccount: cycles
        )
        let extras = await PayoutHistorySupport.loadMissingAchievementPayouts(
            achievements: data.achievements,
            profileID: profileID,
            recorded: history
        )
        WithdrawalsHistoryStore.shared.setAchievementPayouts(extras)
        let combined = (history + extras).sorted { $0.date > $1.date }
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var prop = PayoutHistorySupport.propPayouts(from: combined, accountsByID: accountsByID)
        let linkedAchievements = extras.filter { item in
            item.source == .achievementLive && payoutFirmNames[item.id]?.isEmpty == false
        }
        prop.append(contentsOf: linkedAchievements)
        withdrawalItems = combined
        propPayoutItems = prop
        return prop.reduce(Decimal.zero) { $0 + $1.amount }
    }

    func taxYears(now: Date = .now) -> [Int] {
        var years = Set<Int>([Calendar.current.component(.year, from: now)])
        for expense in ExpenseRecurrenceSchedule.expand(expenses, through: PropFirmExpenseMoney.dayString(from: .now)) {
            if let year = Int(expense.datePaid.prefix(4)), (2000...2100).contains(year) {
                years.insert(year)
            }
        }
        for row in income {
            if let year = Int(row.dateReceived.prefix(4)), (2000...2100).contains(year) {
                years.insert(year)
            }
        }
        for item in propPayoutItems {
            let day = PropFirmExpenseMoney.utcDayString(from: item.date)
            if let year = Int(day.prefix(4)), (2000...2100).contains(year) {
                years.insert(year)
            }
        }
        return years.sorted(by: >)
    }

    func writeTaxExport(
        periodStart: String,
        periodEnd: String,
        kinds: Set<ExpenseTrackerKind> = [.propFirm],
        projectKey: String = "all"
    ) throws -> URL {
        let payoutRows = trackerPayouts.map { item in
            PropFirmExpenseTaxExport.Payout(
                payoutDate: PropFirmExpenseMoney.utcDayString(from: item.date),
                propFirmName: firmName(for: item),
                amount: item.amount
            )
        }
        let through = periodEnd < PropFirmExpenseMoney.dayString(from: .now)
            ? periodEnd
            : PropFirmExpenseMoney.dayString(from: .now)
        let file = PropFirmExpenseTaxExport.trackerFile(
            periodStart: periodStart,
            periodEnd: periodEnd,
            expenses: ExpenseRecurrenceSchedule.expand(expenses, through: through),
            payouts: payoutRows,
            kinds: kinds,
            projectKey: projectKey,
            reservePercent: reservePercent
        )
        return try PropFirmExpenseTaxExport.writeFile(csv: file.csv, filename: file.filename)
    }

    func setReservePercent(_ percent: Decimal) async {
        guard let percent = PropFirmYearOverviewBuilder.normalized(percent) else { return }
        reservePercent = percent
        guard let userID = await data.session.currentUserID else { return }
        do {
            try await PropFirmExpenseRepository(supabase: data.supabase).saveTaxReservePercent(
                userID: ProfileID(userID.rawValue),
                percent: percent
            )
            reserveError = nil
        } catch {
            reserveError = "Couldn't save your tax reserve percentage."
        }
    }

    func adoptAssignments() {
        payoutFirmNames = PropFirmPayoutAssignmentStore.shared.namesByKey
    }

    private var trackerPayouts: [PayoutHistoryItem] {
        var rows = propPayoutItems
        let ids = Set(rows.map(\.id))
        for item in withdrawalItems where item.source == .achievementLive && !ids.contains(item.id) {
            let name = payoutFirmNames[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty { rows.append(item) }
        }
        return rows
    }

    private func firmName(for item: PayoutHistoryItem) -> String {
        if let assigned = payoutFirmNames[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assigned.isEmpty {
            return assigned
        }
        if let linked = PropFirmYearOverviewBuilder.attributedFirmName(accountID: item.accountID, expenses: expenses) {
            return linked
        }
        let inferred = TradingAccountDisplay.inferPropFirmName(accounts.first { $0.id == item.accountID }?.name)
        return inferred.isEmpty ? PropFirmYearOverviewBuilder.unassignedLabel : inferred
    }
}
