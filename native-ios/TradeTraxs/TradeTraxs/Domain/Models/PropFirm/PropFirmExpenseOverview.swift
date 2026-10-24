import Foundation

nonisolated struct PropFirmOverviewPayout: Sendable {
    var payoutDate: String
    var accountID: TradingAccountID?
    var amount: Decimal
    var assignedFirmName: String? = nil
    var accountName: String? = nil
}

nonisolated struct PropFirmProfitability: Identifiable, Hashable, Sendable {
    var id: String { key }
    var key: String
    var label: String
    var spent: Decimal
    var payouts: Decimal
    var net: Decimal
    var shortfall: Decimal
}

nonisolated struct PropFirmMonthComparison: Identifiable, Hashable, Sendable {
    var id: String { monthKey }
    var monthKey: String
    var label: String
    var expenses: Decimal
    var payouts: Decimal
}

nonisolated struct PropFirmYearOverview: Sendable {
    var year: Int
    var payouts: Decimal
    var expenses: Decimal
    var net: Decimal
    var deductibleEstimate: Decimal
    var reserve: Decimal
    var firms: [PropFirmProfitability]
    var mostProfitableFirmKey: String?
    var byCategory: [PropFirmExpenseBreakdown]
    var spendingByFirm: [PropFirmExpenseBreakdown]
    var months: [PropFirmMonthComparison]
}

/// Year-scoped prop firm results. Unassigned payouts are payouts with no single recorded firm.
nonisolated enum PropFirmYearOverviewBuilder {
    static let unassignedKey = "__unassigned__"
    static let unassignedLabel = "Unassigned"
    static let defaultPercent: Decimal = 25
    static let presets: [Decimal] = [15, 20, 25, 30]

    private static let monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func isPreset(_ percent: Decimal) -> Bool {
        let rounded = PropFirmExpenseMoney.rounded(percent)
        return presets.contains { PropFirmExpenseMoney.rounded($0) == rounded }
    }

    static func percentLabel(_ percent: Decimal) -> String {
        let text = PropFirmExpenseMoney.plainDecimalString(percent)
        if text.hasSuffix(".00") { return String(text.dropLast(3)) }
        if text.hasSuffix("0") { return String(text.dropLast()) }
        return text
    }

    static func normalized(_ percent: Decimal) -> Decimal? {
        let rounded = PropFirmExpenseMoney.rounded(percent)
        guard rounded > 0, rounded <= 100 else { return nil }
        return rounded
    }

    static func parsePercent(_ text: String) -> Decimal? {
        let raw = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        guard raw.range(of: #"^\d{1,3}(\.\d{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return normalized(value)
    }

    static func attributedFirmName(accountID: TradingAccountID, expenses: [PropFirmExpense]) -> String? {
        if let purchase = expenses.first(where: {
            $0.accountID == accountID && $0.source == .accountPurchase && !$0.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return purchase.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let linked = expenses.filter {
            $0.accountID == accountID && !$0.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let keys = Set(linked.map { firmKey($0.propFirmName) })
        if keys.count == 1, let name = linked.first?.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines) {
            return name
        }
        return nil
    }

    static func firmName(accountID: TradingAccountID, expenses: [PropFirmExpense]) -> String {
        attributedFirmName(accountID: accountID, expenses: expenses) ?? unassignedLabel
    }

    static func reserve(net: Decimal, percent: Decimal) -> Decimal {
        guard net > 0, let percent = normalized(percent) else { return 0 }
        return PropFirmExpenseMoney.rounded(net * percent / 100)
    }

    static func summarize(
        year: Int,
        expenses: [PropFirmExpense],
        payouts: [PropFirmOverviewPayout],
        reservePercent: Decimal
    ) -> PropFirmYearOverview {
        let start = String(format: "%04d-01-01", year)
        let end = String(format: "%04d-12-31", year)
        let propExpenses = expenses.filter { $0.trackerKind == .propFirm }
        let yearExpenses = propExpenses.filter { $0.datePaid >= start && $0.datePaid <= end }
        let yearPayouts = payouts.filter { $0.payoutDate >= start && $0.payoutDate <= end && $0.amount > 0 }

        var buckets: [String: Bucket] = [:]
        var categories: [PropFirmExpenseType: Decimal] = [:]
        var expenseTotal = Decimal.zero
        var payoutTotal = Decimal.zero

        for expense in yearExpenses {
            expenseTotal += expense.totalCost
            let key = firmKey(expense.propFirmName)
            var bucket = buckets[key] ?? Bucket(label: expense.propFirmName.trimmingCharacters(in: .whitespacesAndNewlines))
            bucket.spent += expense.totalCost
            buckets[key] = bucket
            categories[expense.expenseType, default: .zero] += expense.totalCost
        }

        for payout in yearPayouts {
            payoutTotal += payout.amount
            let explicit = payout.assignedFirmName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let inferred = TradingAccountDisplay.inferPropFirmName(payout.accountName)
            let label = (explicit?.isEmpty == false ? explicit : nil)
                ?? payout.accountID.flatMap { attributedFirmName(accountID: $0, expenses: propExpenses) }
                ?? (inferred.isEmpty ? nil : inferred)
            let key = label.map(firmKey) ?? unassignedKey
            var bucket = buckets[key] ?? Bucket(label: label ?? unassignedLabel)
            bucket.payouts += payout.amount
            buckets[key] = bucket
        }

        let firms = buckets.map { key, bucket in
            PropFirmProfitability(
                key: key,
                label: bucket.label,
                spent: bucket.spent,
                payouts: bucket.payouts,
                net: bucket.payouts - bucket.spent,
                shortfall: max(0, bucket.spent - bucket.payouts)
            )
        }
        .filter { $0.spent > 0 || $0.payouts > 0 }
        .sorted { lhs, rhs in
            if lhs.key == unassignedKey { return false }
            if rhs.key == unassignedKey { return true }
            if lhs.net != rhs.net { return lhs.net > rhs.net }
            if lhs.payouts != rhs.payouts { return lhs.payouts > rhs.payouts }
            return lhs.label < rhs.label
        }

        let spending = firms
            .filter { $0.spent > 0 }
            .sorted { lhs, rhs in
                if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
                return lhs.label < rhs.label
            }
            .map { PropFirmExpenseBreakdown(id: $0.key, label: $0.label, total: $0.spent) }
        let categoryRows = PropFirmExpenseType.allCases.compactMap { type -> PropFirmExpenseBreakdown? in
            guard let total = categories[type], total > 0 else { return nil }
            return PropFirmExpenseBreakdown(id: type.rawValue, label: type.title, total: total)
        }

        return PropFirmYearOverview(
            year: year,
            payouts: payoutTotal,
            expenses: expenseTotal,
            net: payoutTotal - expenseTotal,
            deductibleEstimate: expenseTotal,
            reserve: reserve(net: payoutTotal - expenseTotal, percent: reservePercent),
            firms: firms,
            mostProfitableFirmKey: firms.first { $0.key != unassignedKey }?.key,
            byCategory: categoryRows,
            spendingByFirm: spending,
            months: months(year: year, expenses: yearExpenses, payouts: yearPayouts)
        )
    }

    private static func firmKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func months(
        year: Int,
        expenses: [PropFirmExpense],
        payouts: [PropFirmOverviewPayout]
    ) -> [PropFirmMonthComparison] {
        var months = monthLabels.enumerated().map { index, label in
            PropFirmMonthComparison(
                monthKey: String(format: "%04d-%02d", year, index + 1),
                label: label,
                expenses: 0,
                payouts: 0
            )
        }
        for expense in expenses {
            let key = String(expense.datePaid.prefix(7))
            guard let index = months.firstIndex(where: { $0.monthKey == key }) else { continue }
            months[index].expenses += expense.totalCost
        }
        for payout in payouts {
            let key = String(payout.payoutDate.prefix(7))
            guard let index = months.firstIndex(where: { $0.monthKey == key }) else { continue }
            months[index].payouts += payout.amount
        }
        return months
    }

    private struct Bucket {
        var label: String
        var spent: Decimal = 0
        var payouts: Decimal = 0
    }
}
