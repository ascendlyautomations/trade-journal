import Foundation

/// Owner prop-firm expenses. Account purchase rows are upserted so repeat saves do not duplicate.
nonisolated struct PropFirmExpenseRepository: Sendable {
    private let database: any SupabaseDatabaseExecuting

    init(supabase: SupabaseInfrastructure) {
        self.database = supabase.database
    }

    init(database: any SupabaseDatabaseExecuting) {
        self.database = database
    }

    func list(userID: ProfileID) async throws -> [PropFirmExpense] {
        let rows: [Row] = try await database.select(
            Row.self,
            from: "prop_firm_expenses",
            query: [
                SupabaseQuery.select(Self.selectColumns),
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "order", value: "date_paid.desc,id.desc"),
            ]
        )
        return rows.compactMap(Self.map)
    }

    func accountPurchaseExpense(accountID: TradingAccountID) async throws -> PropFirmExpense? {
        let rows: [Row] = try await database.select(
            Row.self,
            from: "prop_firm_expenses",
            query: [
                SupabaseQuery.select(Self.selectColumns),
                SupabaseQuery.eq("account_id", accountID.rawValue),
                SupabaseQuery.eq("source", PropFirmExpenseSource.accountPurchase.rawValue),
                SupabaseQuery.limit(1),
            ]
        )
        return rows.compactMap(Self.map).first
    }

    func create(userID: ProfileID, draft: PropFirmExpenseDraft) async throws -> PropFirmExpense {
        let body = try Self.writeBody(userID: userID, draft: draft, source: .manual, accountID: draft.accountID)
        let row: Row = try await database.insert(body, into: "prop_firm_expenses", returning: Row.self)
        guard let expense = Self.map(row) else {
            throw AppError.unknown(message: "Couldn't save that expense.")
        }
        return expense
    }

    func update(userID: ProfileID, expense: PropFirmExpense, draft: PropFirmExpenseDraft) async throws -> PropFirmExpense {
        let body = try Self.updateBody(draft: draft, preserveAccountLink: expense.source == .accountPurchase)
        let row: Row = try await database.update(
            body,
            table: "prop_firm_expenses",
            query: [
                SupabaseQuery.eq("id", expense.id),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ],
            returning: Row.self
        )
        guard let saved = Self.map(row) else {
            throw AppError.unknown(message: "Couldn't save that expense.")
        }
        return saved
    }

    func delete(userID: ProfileID, expenseID: String) async throws {
        try await database.delete(
            from: "prop_firm_expenses",
            query: [
                SupabaseQuery.eq("id", expenseID),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
    }

    /// Missing row or an unavailable table uses the 25% budgeting default.
    func taxReservePercent(userID: ProfileID) async -> Decimal {
        do {
            let rows: [SettingsRow] = try await database.select(
                SettingsRow.self,
                from: "prop_firm_expense_settings",
                query: [
                    SupabaseQuery.select("user_id,tax_reserve_percent"),
                    SupabaseQuery.eq("user_id", userID.rawValue),
                    SupabaseQuery.limit(1),
                ]
            )
            guard let value = rows.first?.tax_reserve_percent?.decimal else {
                return PropFirmYearOverviewBuilder.defaultPercent
            }
            return PropFirmYearOverviewBuilder.normalized(value) ?? PropFirmYearOverviewBuilder.defaultPercent
        } catch {
            return PropFirmYearOverviewBuilder.defaultPercent
        }
    }

    func saveTaxReservePercent(userID: ProfileID, percent: Decimal) async throws {
        guard let percent = PropFirmYearOverviewBuilder.normalized(percent) else {
            throw AppError.unknown(message: "Enter a percentage from 0.01 to 100.")
        }
        let _: SettingsRow = try await database.upsert(
            SettingsBody(
                user_id: userID.rawValue,
                tax_reserve_percent: PropFirmExpenseMoney.plainDecimalString(percent)
            ),
            into: "prop_firm_expense_settings",
            onConflict: "user_id",
            returning: SettingsRow.self,
            select: "user_id,tax_reserve_percent"
        )
    }

    func payoutAssignments(userID: ProfileID) async throws -> [String: String] {
        let rows: [AssignmentRow] = try await database.select(
            AssignmentRow.self,
            from: "prop_firm_payout_assignments",
            query: [
                SupabaseQuery.select("payout_key,prop_firm_name"),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
        var names: [String: String] = [:]
        for row in rows {
            guard let key = row.payout_key, Self.isPayoutKey(key),
                  let name = row.prop_firm_name.flatMap(Self.normalizedFirmName) else { continue }
            names[key] = name
        }
        return names
    }

    func savePayoutAssignment(userID: ProfileID, payoutKey: String, firmName: String) async throws {
        guard Self.isPayoutKey(payoutKey) else {
            throw AppError.unknown(message: "That payout cannot be assigned.")
        }
        guard let name = Self.normalizedFirmName(firmName) else {
            throw AppError.unknown(message: "Enter a prop firm name.")
        }
        let _: AssignmentRow = try await database.upsert(
            AssignmentBody(user_id: userID.rawValue, payout_key: payoutKey, prop_firm_name: name),
            into: "prop_firm_payout_assignments",
            onConflict: "user_id,payout_key",
            returning: AssignmentRow.self,
            select: "payout_key,prop_firm_name"
        )
    }

    func clearPayoutAssignment(userID: ProfileID, payoutKey: String) async throws {
        guard Self.isPayoutKey(payoutKey) else {
            throw AppError.unknown(message: "That payout cannot be assigned.")
        }
        try await database.delete(
            from: "prop_firm_payout_assignments",
            query: [
                SupabaseQuery.eq("user_id", userID.rawValue),
                SupabaseQuery.eq("payout_key", payoutKey),
            ]
        )
    }

    static func normalizedFirmName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...120).contains(name.count) else { return nil }
        return name
    }

    static func isPayoutKey(_ value: String) -> Bool {
        value.range(of: #"^(ledger|cycle|achievement):[0-9a-fA-F-]{36}$"#, options: .regularExpression) != nil
    }

    /// Creates or updates the single purchase expense for an account. Blank cost is a no-op.
    func syncAccountPurchase(
        userID: ProfileID,
        accountID: TradingAccountID,
        draft: TradingAccountDraft
    ) async throws {
        guard let expenseType = PropFirmExpenseType.accountPurchaseType(
            category: draft.category,
            mode: draft.mode
        ), let cost = PropFirmExpenseMoney.parse(draft.purchaseCostDigits) else {
            return
        }
        struct Body: Encodable {
            var p_account_id: String
            var p_user_id: String
            var p_cost_per_account: String
            var p_prop_firm_name: String
            var p_expense_type: String
            var p_date_paid: String
        }
        let body = Body(
            p_account_id: accountID.rawValue,
            p_user_id: userID.rawValue,
            p_cost_per_account: PropFirmExpenseMoney.plainDecimalString(cost),
            p_prop_firm_name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            p_expense_type: expenseType.rawValue,
            p_date_paid: PropFirmExpenseMoney.dayString(from: draft.purchaseDate ?? .now)
        )
        let data = try await database.rpcData(
            functionName: "upsert_prop_firm_account_purchase_expense",
            parametersJSON: try JSONEncoder().encode(body)
        )
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty || raw == "null" {
            throw AppError.unknown(message: "Couldn't record the account purchase cost.")
        }
    }

    private static let selectColumns =
        "id,user_id,prop_firm_name,expense_type,cost_per_account,quantity,total_cost,date_paid,payment_label,notes,account_id,source,tracker_kind,project_label,custom_category,recurrence"

    private static func map(_ row: Row) -> PropFirmExpense? {
        guard let id = row.id, !id.isEmpty,
              let type = PropFirmExpenseType(rawValue: row.expense_type ?? ""),
              let cost = row.cost_per_account?.decimal,
              let quantity = row.quantity
        else { return nil }
        let total = row.total_cost?.decimal ?? PropFirmExpenseMoney.total(cost: cost, quantity: quantity)
        let source = PropFirmExpenseSource(rawValue: row.source ?? "") ?? .manual
        return PropFirmExpense(
            id: id,
            propFirmName: (row.prop_firm_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            expenseType: type,
            costPerAccount: cost,
            quantity: quantity,
            totalCost: total,
            datePaid: String((row.date_paid ?? "").prefix(10)),
            paymentLabel: row.payment_label,
            notes: row.notes,
            accountID: row.account_id.flatMap { $0.isEmpty ? nil : TradingAccountID($0) },
            source: source,
            trackerKind: ExpenseTrackerKind(rawValue: row.tracker_kind ?? "") ?? .propFirm,
            projectLabel: row.project_label,
            customCategory: row.custom_category,
            recurrence: ExpenseRecurrence(rawValue: row.recurrence ?? "")
        )
    }

    private static func writeBody(
        userID: ProfileID,
        draft: PropFirmExpenseDraft,
        source: PropFirmExpenseSource,
        accountID: TradingAccountID?
    ) throws -> WriteBody {
        guard let cost = PropFirmExpenseMoney.parse(draft.costDigits),
              let quantity = Int(draft.quantityDigits)
        else {
            throw AppError.unknown(message: "Enter a cost greater than zero.")
        }
        let propFirm = draft.trackerKind == .propFirm
        return WriteBody(
            user_id: userID.rawValue,
            prop_firm_name: draft.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines),
            expense_type: propFirm ? draft.expenseType.rawValue : PropFirmExpenseType.other.rawValue,
            cost_per_account: PropFirmExpenseMoney.plainDecimalString(cost),
            quantity: quantity,
            date_paid: PropFirmExpenseMoney.dayString(from: draft.datePaid),
            payment_label: blankToNil(draft.paymentLabel),
            notes: blankToNil(draft.notes),
            account_id: propFirm ? accountID?.rawValue : nil,
            source: source.rawValue,
            tracker_kind: draft.trackerKind.rawValue,
            project_label: propFirm ? nil : blankToNil(draft.projectLabel),
            custom_category: propFirm ? nil : blankToNil(draft.customCategory),
            recurrence: draft.recurrence?.rawValue
        )
    }

    private static func updateBody(
        draft: PropFirmExpenseDraft,
        preserveAccountLink: Bool
    ) throws -> UpdateBody {
        guard let cost = PropFirmExpenseMoney.parse(draft.costDigits),
              let quantity = Int(draft.quantityDigits)
        else {
            throw AppError.unknown(message: "Enter a cost greater than zero.")
        }
        let propFirm = draft.trackerKind == .propFirm
        return UpdateBody(
            prop_firm_name: draft.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines),
            expense_type: propFirm ? draft.expenseType.rawValue : PropFirmExpenseType.other.rawValue,
            cost_per_account: PropFirmExpenseMoney.plainDecimalString(cost),
            quantity: quantity,
            date_paid: PropFirmExpenseMoney.dayString(from: draft.datePaid),
            payment_label: blankToNil(draft.paymentLabel),
            notes: blankToNil(draft.notes),
            account_id: propFirm && !preserveAccountLink ? draft.accountID?.rawValue : nil,
            includeAccount: !preserveAccountLink && propFirm,
            tracker_kind: draft.trackerKind.rawValue,
            project_label: propFirm ? nil : blankToNil(draft.projectLabel),
            custom_category: propFirm ? nil : blankToNil(draft.customCategory),
            recurrence: draft.recurrence?.rawValue
        )
    }

    private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct AssignmentRow: Decodable, Sendable {
        var payout_key: String?
        var prop_firm_name: String?
    }

    private struct AssignmentBody: Encodable {
        var user_id: String
        var payout_key: String
        var prop_firm_name: String
    }

    private struct SettingsRow: Decodable, Sendable {
        var user_id: String?
        var tax_reserve_percent: FlexibleNumber?
    }

    private struct SettingsBody: Encodable {
        var user_id: String
        var tax_reserve_percent: String
    }

    private struct Row: Decodable, Sendable {
        var id: String?
        var user_id: String?
        var prop_firm_name: String?
        var expense_type: String?
        var cost_per_account: FlexibleNumber?
        var quantity: Int?
        var total_cost: FlexibleNumber?
        var date_paid: String?
        var payment_label: String?
        var notes: String?
        var account_id: String?
        var source: String?
        var tracker_kind: String?
        var project_label: String?
        var custom_category: String?
        var recurrence: String?
    }

    private struct WriteBody: Encodable {
        var user_id: String
        var prop_firm_name: String
        var expense_type: String
        var cost_per_account: String
        var quantity: Int
        var date_paid: String
        var payment_label: String?
        var notes: String?
        var account_id: String?
        var source: String
        var tracker_kind: String
        var project_label: String?
        var custom_category: String?
        var recurrence: String?
    }

    private struct UpdateBody: Encodable {
        var prop_firm_name: String
        var expense_type: String
        var cost_per_account: String
        var quantity: Int
        var date_paid: String
        var payment_label: String?
        var notes: String?
        var account_id: String?
        var includeAccount: Bool
        var tracker_kind: String
        var project_label: String?
        var custom_category: String?
        var recurrence: String?

        enum CodingKeys: String, CodingKey {
            case prop_firm_name
            case expense_type
            case cost_per_account
            case quantity
            case date_paid
            case payment_label
            case notes
            case account_id
            case tracker_kind
            case project_label
            case custom_category
            case recurrence
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(prop_firm_name, forKey: .prop_firm_name)
            try container.encode(expense_type, forKey: .expense_type)
            try container.encode(cost_per_account, forKey: .cost_per_account)
            try container.encode(quantity, forKey: .quantity)
            try container.encode(date_paid, forKey: .date_paid)
            try container.encode(payment_label, forKey: .payment_label)
            try container.encode(notes, forKey: .notes)
            if includeAccount {
                try container.encode(account_id, forKey: .account_id)
            }
            try container.encode(tracker_kind, forKey: .tracker_kind)
            try container.encode(project_label, forKey: .project_label)
            try container.encode(custom_category, forKey: .custom_category)
            try container.encode(recurrence, forKey: .recurrence)
        }
    }

    func saveCategory(userID: ProfileID, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmed.count) else { return }
        struct Body: Encodable { var user_id: String; var name: String }
        struct Saved: Decodable { var name: String? }
        let _: Saved? = try? await database.upsert(
            Body(user_id: userID.rawValue, name: trimmed),
            into: "expense_categories",
            onConflict: "user_id,name",
            returning: Saved.self,
            select: "name"
        )
    }

    func categories(userID: ProfileID) async -> [String] {
        struct Saved: Decodable { var name: String? }
        let rows: [Saved] = (try? await database.select(
            Saved.self,
            from: "expense_categories",
            query: [
                SupabaseQuery.select("name"),
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "order", value: "name.asc"),
            ]
        )) ?? []
        return rows.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func listIncome(userID: ProfileID) async throws -> [TrackerIncome] {
        let rows: [IncomeRow] = try await database.select(
            IncomeRow.self,
            from: "tracker_income",
            query: [
                SupabaseQuery.select(Self.incomeColumns),
                SupabaseQuery.eq("user_id", userID.rawValue),
                URLQueryItem(name: "order", value: "date_received.desc,id.desc"),
            ]
        )
        return rows.compactMap(Self.mapIncome)
    }

    func createIncome(userID: ProfileID, draft: TrackerIncomeDraft) async throws -> TrackerIncome {
        let body = try Self.incomeWrite(userID: userID, draft: draft)
        let row: IncomeRow = try await database.insert(body, into: "tracker_income", returning: IncomeRow.self)
        guard let income = Self.mapIncome(row) else {
            throw AppError.unknown(message: "Couldn't save that income.")
        }
        return income
    }

    func updateIncome(userID: ProfileID, incomeID: String, draft: TrackerIncomeDraft) async throws -> TrackerIncome {
        let body = try Self.incomeUpdate(draft: draft)
        let row: IncomeRow = try await database.update(
            body,
            table: "tracker_income",
            query: [
                SupabaseQuery.eq("id", incomeID),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ],
            returning: IncomeRow.self
        )
        guard let income = Self.mapIncome(row) else {
            throw AppError.unknown(message: "Couldn't save that income.")
        }
        return income
    }

    func deleteIncome(userID: ProfileID, incomeID: String) async throws {
        try await database.delete(
            from: "tracker_income",
            query: [
                SupabaseQuery.eq("id", incomeID),
                SupabaseQuery.eq("user_id", userID.rawValue),
            ]
        )
    }

    private static let incomeColumns =
        "id,user_id,income_kind,name,project_label,amount,date_received,payment_label,notes,recurrence"

    private static func mapIncome(_ row: IncomeRow) -> TrackerIncome? {
        guard let id = row.id, !id.isEmpty,
              let kind = TrackerIncomeKind(rawValue: row.income_kind ?? ""),
              let amount = row.amount?.decimal,
              amount > 0
        else { return nil }
        return TrackerIncome(
            id: id,
            incomeKind: kind,
            name: (row.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            projectLabel: row.project_label,
            amount: amount,
            dateReceived: String((row.date_received ?? "").prefix(10)),
            paymentLabel: row.payment_label,
            notes: row.notes,
            recurrence: ExpenseRecurrence(rawValue: row.recurrence ?? "")
        )
    }

    private static func incomeWrite(userID: ProfileID, draft: TrackerIncomeDraft) throws -> IncomeWrite {
        guard let amount = PropFirmExpenseMoney.parse(draft.amountDigits) else {
            throw AppError.unknown(message: "Enter an amount greater than zero.")
        }
        return IncomeWrite(
            user_id: userID.rawValue,
            income_kind: draft.incomeKind.rawValue,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            project_label: draft.incomeKind == .business ? blankToNil(draft.projectLabel) : nil,
            amount: PropFirmExpenseMoney.plainDecimalString(amount),
            date_received: PropFirmExpenseMoney.dayString(from: draft.dateReceived),
            payment_label: blankToNil(draft.paymentLabel),
            notes: blankToNil(draft.notes),
            recurrence: draft.recurrence?.rawValue
        )
    }

    private static func incomeUpdate(draft: TrackerIncomeDraft) throws -> IncomeUpdate {
        guard let amount = PropFirmExpenseMoney.parse(draft.amountDigits) else {
            throw AppError.unknown(message: "Enter an amount greater than zero.")
        }
        return IncomeUpdate(
            income_kind: draft.incomeKind.rawValue,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            project_label: draft.incomeKind == .business ? blankToNil(draft.projectLabel) : nil,
            amount: PropFirmExpenseMoney.plainDecimalString(amount),
            date_received: PropFirmExpenseMoney.dayString(from: draft.dateReceived),
            payment_label: blankToNil(draft.paymentLabel),
            notes: blankToNil(draft.notes),
            recurrence: draft.recurrence?.rawValue
        )
    }

    private struct IncomeRow: Decodable, Sendable {
        var id: String?
        var income_kind: String?
        var name: String?
        var project_label: String?
        var amount: FlexibleNumber?
        var date_received: String?
        var payment_label: String?
        var notes: String?
        var recurrence: String?
    }

    private struct IncomeWrite: Encodable {
        var user_id: String
        var income_kind: String
        var name: String
        var project_label: String?
        var amount: String
        var date_received: String
        var payment_label: String?
        var notes: String?
        var recurrence: String?
    }

    private struct IncomeUpdate: Encodable {
        var income_kind: String
        var name: String
        var project_label: String?
        var amount: String
        var date_received: String
        var payment_label: String?
        var notes: String?
        var recurrence: String?
    }
}
