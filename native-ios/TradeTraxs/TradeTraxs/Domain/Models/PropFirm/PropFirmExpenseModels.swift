import Foundation

nonisolated enum PropFirmExpenseType: String, CaseIterable, Hashable, Codable, Sendable {
    case evaluationPurchase = "evaluation_purchase"
    case activationFee = "activation_fee"
    case resetFee = "reset_fee"
    case subscriptionRenewal = "subscription_renewal"
    case other

    var title: String {
        switch self {
        case .evaluationPurchase: return "Evaluation"
        case .activationFee: return "Activation"
        case .resetFee: return "Reset"
        case .subscriptionRenewal: return "Renewal"
        case .other: return "Other"
        }
    }

    static func accountPurchaseType(
        category: TradingAccountCategory,
        mode: TradingAccountMode
    ) -> PropFirmExpenseType? {
        guard category == .propFirm else { return nil }
        switch mode {
        case .evaluation: return .evaluationPurchase
        case .funded: return .activationFee
        default: return nil
        }
    }
}

nonisolated enum ExpenseRecurrence: String, CaseIterable, Hashable, Codable, Sendable {
    case weekly
    case monthly
    case yearly

    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

nonisolated enum ExpenseRecurrenceSchedule {
    static func dates(from start: String, recurrence: ExpenseRecurrence?, through: String) -> [String] {
        guard start <= through, start.count == 10, through.count == 10 else { return [] }
        guard let recurrence else { return [start] }
        let parts = start.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return [] }
        let anchorYear = parts[0]
        let anchorMonth = parts[1]
        let anchorDay = parts[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var rows: [String] = []
        for index in 0..<2000 {
            let day: String
            switch recurrence {
            case .weekly:
                var components = DateComponents()
                components.year = anchorYear
                components.month = anchorMonth
                components.day = anchorDay + (index * 7)
                components.timeZone = calendar.timeZone
                guard let date = calendar.date(from: components) else { return rows }
                day = PropFirmExpenseMoney.dayString(from: date, calendar: calendar)
            case .monthly:
                let zero = anchorYear * 12 + (anchorMonth - 1) + index
                day = clamped(year: zero / 12, month: (zero % 12) + 1, anchorDay: anchorDay)
            case .yearly:
                day = clamped(year: anchorYear + index, month: anchorMonth, anchorDay: anchorDay)
            }
            if day > through { break }
            rows.append(day)
        }
        return rows
    }

    static func expand(_ expenses: [PropFirmExpense], through: String) -> [PropFirmExpense] {
        expenses.flatMap { expense in
            let days = dates(from: expense.datePaid, recurrence: expense.recurrence, through: through)
            if days.count <= 1 {
                var row = expense
                if row.seriesID.isEmpty { row.seriesID = expense.id }
                return [row]
            }
            return days.map { day in
                var row = expense
                row.seriesID = expense.id
                row.id = "\(expense.id):\(day)"
                row.datePaid = day
                return row
            }
        }
    }

    private static func clamped(year: Int, month: Int, anchorDay: Int) -> String {
        let last = daysInMonth(year: year, month: month)
        let day = min(anchorDay, last)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(year: year, month: month, day: 1)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 28 }
        return range.count
    }
}

nonisolated enum ExpenseTrackerKind: String, CaseIterable, Hashable, Codable, Sendable {
    case propFirm = "prop_firm"
    case business
    case tradingTools = "trading_tools"
    case other

    var title: String {
        switch self {
        case .propFirm: return "Prop Firm"
        case .business: return "Business"
        case .tradingTools: return "Trading Tools"
        case .other: return "Other"
        }
    }
}

nonisolated enum PropFirmExpenseSource: String, Hashable, Codable, Sendable {
    case manual
    case accountPurchase = "account_purchase"
}

nonisolated struct PropFirmExpense: Identifiable, Hashable, Sendable {
    var id: String
    var propFirmName: String
    var expenseType: PropFirmExpenseType
    var costPerAccount: Decimal
    var quantity: Int
    var totalCost: Decimal
    var datePaid: String
    var paymentLabel: String?
    var notes: String?
    var accountID: TradingAccountID?
    var source: PropFirmExpenseSource
    var trackerKind: ExpenseTrackerKind = .propFirm
    var projectLabel: String? = nil
    var customCategory: String? = nil
    var recurrence: ExpenseRecurrence? = nil
    var seriesID: String = ""

    var savedID: String { seriesID.isEmpty ? id : seriesID }

    var categoryTitle: String {
        trackerKind == .propFirm ? expenseType.title : (customCategory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? customCategory! : "Uncategorized")
    }

    var projectTitle: String {
        if trackerKind == .propFirm { return propFirmName }
        let label = projectLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? "No project" : label
    }

    var accountPurchaseIdentity: String? {
        guard source == .accountPurchase, let accountID else { return nil }
        return "account_purchase:\(accountID.rawValue)"
    }
}

nonisolated struct PropFirmExpenseDraft: Hashable, Sendable {
    var propFirmName: String
    var expenseType: PropFirmExpenseType
    var costDigits: String
    var quantityDigits: String
    var datePaid: Date
    var paymentLabel: String
    var notes: String
    var accountID: TradingAccountID?
    var trackerKind: ExpenseTrackerKind = .propFirm
    var projectLabel: String = ""
    var customCategory: String = ""
    var recurrence: ExpenseRecurrence? = nil

    static func empty(now: Date = .now) -> PropFirmExpenseDraft {
        PropFirmExpenseDraft(
            propFirmName: "",
            expenseType: .evaluationPurchase,
            costDigits: "",
            quantityDigits: "1",
            datePaid: now,
            paymentLabel: "",
            notes: "",
            accountID: nil
        )
    }

    static func from(_ expense: PropFirmExpense) -> PropFirmExpenseDraft {
        PropFirmExpenseDraft(
            propFirmName: expense.propFirmName,
            expenseType: expense.expenseType,
            costDigits: PropFirmExpenseMoney.editingText(expense.costPerAccount),
            quantityDigits: String(expense.quantity),
            datePaid: PropFirmExpenseMoney.date(fromDay: expense.datePaid) ?? .now,
            paymentLabel: expense.paymentLabel ?? "",
            notes: expense.notes ?? "",
            accountID: expense.accountID,
            trackerKind: expense.trackerKind,
            projectLabel: expense.projectLabel ?? "",
            customCategory: expense.customCategory ?? "",
            recurrence: expense.recurrence
        )
    }
}

nonisolated struct PropFirmExpenseFilter: Hashable, Sendable {
    var firmKey: String = "all"
    var category: PropFirmExpenseType?
    var customCategory: String?
    var fromDay: String?
    var toDay: String?
    var kind: ExpenseTrackerKind?
    var projectKey: String = "all"
}

nonisolated struct PropFirmExpenseBreakdown: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var total: Decimal
}

nonisolated struct PropFirmExpenseMonthPoint: Identifiable, Hashable, Sendable {
    var id: String { monthKey }
    var monthKey: String
    var label: String
    var total: Decimal
}

nonisolated struct PropFirmExpenseAnalytics: Hashable, Sendable {
    var totalSpent: Decimal
    var totalAccountsPurchased: Int
    var totalPayouts: Decimal
    var netProfit: Decimal
    var byFirm: [PropFirmExpenseBreakdown]
    var byCategory: [PropFirmExpenseBreakdown]
    var monthly: [PropFirmExpenseMonthPoint]
}

nonisolated enum PropFirmExpenseMoney {
    static func parse(_ display: String) -> Decimal? {
        let plain = NumericInputFieldSupport.plainNumericString(from: display)
        guard !plain.isEmpty, let value = Decimal(string: plain), value > 0 else { return nil }
        return rounded(value)
    }

    static func total(cost: Decimal, quantity: Int) -> Decimal {
        rounded(cost * Decimal(quantity))
    }

    static func editingText(_ value: Decimal) -> String {
        NumericInputFieldSupport.seedEditingText(from: rounded(value), style: .unsignedCurrency)
    }

    static func format(_ value: Decimal) -> String {
        NumberDisplay.currency(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    static func utcDayString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return dayString(from: date, calendar: calendar)
    }

    static func dayString(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(fromDay day: String, calendar: Calendar = .current) -> Date? {
        let pieces = day.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    static func plainDecimalString(_ value: Decimal) -> String {
        let rounded = rounded(value)
        let number = NSDecimalNumber(decimal: rounded)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: number) ?? "0.00"
    }
}

nonisolated enum PropFirmExpenseAnalyticsBuilder {
    static func summarize(
        expenses: [PropFirmExpense],
        payouts: Decimal,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PropFirmExpenseAnalytics {
        var totalSpent = Decimal.zero
        var accounts = 0
        var firms: [String: (label: String, total: Decimal)] = [:]
        var categories: [PropFirmExpenseType: Decimal] = [:]

        for expense in expenses {
            totalSpent += expense.totalCost
            accounts += expense.quantity
            let key = expense.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var firm = firms[key] ?? (expense.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines), .zero)
            firm.total += expense.totalCost
            firms[key] = firm
            categories[expense.expenseType, default: .zero] += expense.totalCost
        }

        let byFirm = firms.values
            .map { PropFirmExpenseBreakdown(id: $0.label, label: $0.label, total: $0.total) }
            .sorted { lhs, rhs in
                if lhs.total == rhs.total { return lhs.label < rhs.label }
                return lhs.total > rhs.total
            }
        let byCategory = PropFirmExpenseType.allCases.compactMap { type -> PropFirmExpenseBreakdown? in
            guard let total = categories[type], total > 0 else { return nil }
            return PropFirmExpenseBreakdown(id: type.rawValue, label: type.title, total: total)
        }

        return PropFirmExpenseAnalytics(
            totalSpent: totalSpent,
            totalAccountsPurchased: accounts,
            totalPayouts: payouts,
            netProfit: payouts - totalSpent,
            byFirm: byFirm,
            byCategory: byCategory,
            monthly: monthlyTrend(expenses: expenses, now: now, calendar: calendar)
        )
    }

    static func filter(_ expenses: [PropFirmExpense], with filter: PropFirmExpenseFilter) -> [PropFirmExpense] {
        expenses.filter { expense in
            if filter.firmKey != "all" {
                let key = expense.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if key != filter.firmKey { return false }
            }
            if let kind = filter.kind, expense.trackerKind != kind { return false }
            if filter.projectKey != "all" {
                let key = (expense.projectLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if key != filter.projectKey { return false }
            }
            if let category = filter.category {
                if expense.trackerKind != .propFirm || expense.expenseType != category { return false }
            }
            if let custom = filter.customCategory?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !custom.isEmpty {
                let value = (expense.customCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if value != custom { return false }
            }
            if let from = filter.fromDay, expense.datePaid < from { return false }
            if let to = filter.toDay, expense.datePaid > to { return false }
            return true
        }
    }

    static func validate(_ draft: PropFirmExpenseDraft, today: String) -> String? {
        let name = draft.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.trackerKind == .propFirm {
            if name.isEmpty { return "Enter the prop firm name." }
            if name.count > 120 { return "Prop firm name is too long." }
        } else {
            if name.isEmpty { return "Enter a vendor or name." }
            if name.count > 120 { return "Name is too long." }
            let category = draft.customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            if category.isEmpty { return "Choose or enter a category." }
            if category.count > 80 { return "Category is too long." }
            if draft.projectLabel.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
                return "Business or project label is too long."
            }
        }
        guard PropFirmExpenseMoney.parse(draft.costDigits) != nil else {
            return "Enter a cost greater than zero."
        }
        guard let quantity = Int(draft.quantityDigits), (1...10_000).contains(quantity) else {
            return "Enter an account quantity from 1 to 10,000."
        }
        let day = PropFirmExpenseMoney.dayString(from: draft.datePaid)
        if day > today { return "Purchase date cannot be in the future." }
        if draft.paymentLabel.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
            return "Bank or card label is too long."
        }
        if draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).count > 500 {
            return "Notes are too long."
        }
        return nil
    }

    static func monthlyTrend(
        expenses: [PropFirmExpense],
        now: Date,
        calendar: Calendar
    ) -> [PropFirmExpenseMonthPoint] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        var points: [PropFirmExpenseMonthPoint] = []
        for offset in stride(from: 11, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: start) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: date)
            let key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 1)
            let label = date.formatted(.dateTime.month(.abbreviated))
            points.append(PropFirmExpenseMonthPoint(monthKey: key, label: label, total: .zero))
        }
        var index = Dictionary(uniqueKeysWithValues: points.enumerated().map { ($1.monthKey, $0) })
        for expense in expenses {
            let key = String(expense.datePaid.prefix(7))
            guard let position = index[key] else { continue }
            points[position].total += expense.totalCost
            index[key] = position
        }
        return points
    }
}
