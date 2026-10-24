import Foundation

/// Spreadsheet CSV for a selected reporting period.
/// The deductible line is an unverified estimate, not a tax determination.
nonisolated enum PropFirmExpenseTaxExport {
    struct Payout: Sendable {
        var payoutDate: String
        var propFirmName: String
        var amount: Decimal
    }

    static let disclaimer = "Financial tracking record for the selected period. Potentially deductible expenses are an unverified estimate equal to total recorded expenses. This file does not determine tax treatment or tax liability. Any estimated tax reserve is a budgeting estimate, not a tax calculation or tax liability."

    static func yearPeriod(_ year: Int) -> (start: String, end: String)? {
        guard (2000...2100).contains(year) else { return nil }
        return ("\(year)-01-01", "\(year)-12-31")
    }

    static func customPeriod(from: String, to: String) -> (start: String, end: String)? {
        guard isDay(from), isDay(to), from <= to else { return nil }
        return (from, to)
    }

    static func filename(start: String, end: String) -> String {
        if start.hasSuffix("-01-01"), end.hasSuffix("-12-31"), start.prefix(4) == end.prefix(4) {
            return "tradetraxs-prop-firm-expenses-\(start.prefix(4)).csv"
        }
        return "tradetraxs-prop-firm-expenses-\(start)-to-\(end).csv"
    }

    static func csv(
        periodStart: String,
        periodEnd: String,
        expenses: [PropFirmExpense],
        payouts: [Payout],
        reservePercent: Decimal? = nil
    ) -> String {
        let expenses = expenses
            .filter { inPeriod($0.datePaid, start: periodStart, end: periodEnd) }
            .sorted { lhs, rhs in
                if lhs.datePaid == rhs.datePaid { return lhs.propFirmName < rhs.propFirmName }
                return lhs.datePaid < rhs.datePaid
            }
        let payouts = payouts
            .filter { inPeriod($0.payoutDate, start: periodStart, end: periodEnd) }
            .sorted { lhs, rhs in
                if lhs.payoutDate == rhs.payoutDate { return lhs.propFirmName < rhs.propFirmName }
                return lhs.payoutDate < rhs.payoutDate
            }
        let expenseTotal = expenses.reduce(Decimal.zero) { $0 + $1.totalCost }
        let payoutTotal = payouts.reduce(Decimal.zero) { $0 + $1.amount }
        var lines: [String] = [
            row([text("TradeTraxs Prop Firm Expense Tracker")]),
            row([text("Disclaimer"), text(disclaimer)]),
            row([text("Period Start"), value(periodStart)]),
            row([text("Period End"), value(periodEnd)]),
            row([]),
            row([text("Summary")]),
            row([text("Total Recorded Expenses"), value(money(expenseTotal))]),
            row([text("Total Recorded Payouts"), value(money(payoutTotal))]),
            row([text("Net Payouts After Expenses"), value(money(payoutTotal - expenseTotal))]),
            row([text("Potentially Deductible Expenses (unverified estimate)"), value(money(expenseTotal))]),
        ]
        if let reservePercent {
            let reserve = PropFirmYearOverviewBuilder.reserve(
                net: payoutTotal - expenseTotal,
                percent: reservePercent
            )
            lines.append(row([
                text("Estimated Tax Reserve (\(PropFirmYearOverviewBuilder.percentLabel(reservePercent))% budgeting estimate)"),
                value(money(reserve)),
            ]))
        }
        lines.append(contentsOf: [
            row([]),
            row([text("Expenses")]),
            row([
                text("Purchase Date"),
                text("Prop Firm Name"),
                text("Expense Type"),
                text("Bank/Card Paid With"),
                text("Cost Per Account"),
                text("Quantity"),
                text("Total Cost"),
            ]),
        ])
        lines.append(contentsOf: expenses.map { expense in
            row([
                value(expense.datePaid),
                text(expense.propFirmName),
                text(expense.expenseType.title),
                text(expense.paymentLabel ?? ""),
                value(money(expense.costPerAccount)),
                value(String(expense.quantity)),
                value(money(expense.totalCost)),
            ])
        })
        lines.append(row([]))
        lines.append(row([text("Payouts")]))
        lines.append(row([text("Payout Date"), text("Prop Firm Name"), text("Amount")]))
        lines.append(contentsOf: payouts.map { payout in
            row([
                value(payout.payoutDate),
                text(payout.propFirmName),
                value(money(payout.amount)),
            ])
        })
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func trackerFile(
        periodStart: String,
        periodEnd: String,
        expenses: [PropFirmExpense],
        payouts: [Payout],
        kinds: Set<ExpenseTrackerKind>,
        projectKey: String,
        reservePercent: Decimal?
    ) -> (csv: String, filename: String) {
        let project = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = expenses.filter { expense in
            guard kinds.contains(expense.trackerKind) else { return false }
            if !project.isEmpty, project != "all" {
                let label = (expense.projectLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if label != project { return false }
            }
            return inPeriod(expense.datePaid, start: periodStart, end: periodEnd)
        }
        if kinds == [.propFirm], project.isEmpty || project == "all" {
            return (
                csv(
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    expenses: rows,
                    payouts: payouts,
                    reservePercent: reservePercent
                ),
                filename(start: periodStart, end: periodEnd)
            )
        }
        let includePayouts = kinds.contains(.propFirm)
        let periodPayouts = includePayouts
            ? payouts.filter { inPeriod($0.payoutDate, start: periodStart, end: periodEnd) }
            : []
        let expenseTotal = rows.reduce(Decimal.zero) { $0 + $1.totalCost }
        let propExpenseTotal = rows.filter { $0.trackerKind == .propFirm }.reduce(Decimal.zero) { $0 + $1.totalCost }
        let payoutTotal = periodPayouts.reduce(Decimal.zero) { $0 + $1.amount }
        var lines = [
            row([text("TradeTraxs Expense Tracker")]),
            row([text("Disclaimer"), text("Financial tracking record for the selected period. Totals are recorded expenses and, when prop firm rows are included, recorded prop firm payouts. This file does not determine tax treatment, deductions, or tax liability.")]),
            row([text("Period Start"), value(periodStart)]),
            row([text("Period End"), value(periodEnd)]),
            row([]),
            row([text("Summary")]),
            row([text("Total Recorded Expenses"), value(money(expenseTotal))]),
        ]
        if includePayouts {
            lines.append(row([text("Total Recorded Prop Firm Payouts"), value(money(payoutTotal))]))
            lines.append(row([text("Net Prop Firm Payouts After Prop Firm Expenses"), value(money(payoutTotal - propExpenseTotal))]))
        }
        lines.append(row([]))
        lines.append(row([text("Expenses")]))
        lines.append(row([
            text("Purchase Date"), text("Expense Type"), text("Name"), text("Business/Project"),
            text("Category"), text("Bank/Card Paid With"), text("Amount"), text("Quantity"), text("Total Cost"),
        ]))
        lines.append(contentsOf: rows.map { expense in
            row([
                value(expense.datePaid),
                text(expense.trackerKind.title),
                text(expense.propFirmName),
                text(expense.projectLabel ?? ""),
                text(expense.categoryTitle),
                text(expense.paymentLabel ?? ""),
                value(money(expense.costPerAccount)),
                value(String(expense.quantity)),
                value(money(expense.totalCost)),
            ])
        })
        if includePayouts {
            lines.append(row([]))
            lines.append(row([text("Payouts")]))
            lines.append(row([text("Payout Date"), text("Prop Firm Name"), text("Amount")]))
            lines.append(contentsOf: periodPayouts.map { payout in
                row([value(payout.payoutDate), text(payout.propFirmName), value(money(payout.amount))])
            })
        }
        return ("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n", "tradetraxs-expenses-\(periodStart)-to-\(periodEnd).csv")
    }

    static func writeFile(csv: String, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PropFirmExpenseExport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        guard let data = csv.data(using: .utf8) else {
            throw AppError.unknown(message: "Couldn't create the CSV file.")
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func inPeriod(_ day: String, start: String, end: String) -> Bool {
        day >= start && day <= end
    }

    private static func isDay(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func money(_ value: Decimal) -> String {
        PropFirmExpenseMoney.plainDecimalString(value)
    }

    private static func text(_ value: String) -> String {
        cell(neutralize(value))
    }

    private static func value(_ cellValue: String) -> String {
        cell(cellValue)
    }

    private static func row(_ cells: [String]) -> String {
        cells.joined(separator: ",")
    }

    private static func cell(_ value: String) -> String {
        if value.contains("\"") || value.contains(",") || value.contains("\r") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func neutralize(_ value: String) -> String {
        guard let first = value.first, "=+@\t\r".contains(first) else { return value }
        return "'" + value
    }
}
