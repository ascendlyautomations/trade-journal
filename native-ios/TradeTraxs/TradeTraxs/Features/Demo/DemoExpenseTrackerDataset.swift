import Foundation

/// Six-month TraxsPro Expense Tracker preview book, isolated from Supabase and owner stores.
nonisolated enum DemoExpenseTrackerDataset {
    struct Bundle: Sendable {
        var expenses: [PropFirmExpense]
        var income: [TrackerIncome]
        var accounts: [TradingAccount]
        var payoutItems: [PayoutHistoryItem]
        var payoutFirmNames: [String: String]
        var savedCategories: [String]
    }

    struct YearTotals: Sendable {
        var expandedExpenseTotal: Decimal
        var propExpenseTotal: Decimal
        var payoutTotal: Decimal
        var net: Decimal
        var deductibleEstimate: Decimal
    }

    static let previewAccountIDs = (
        apexEval: TradingAccountID("demo.expense.apex.eval"),
        topstepFunded: TradingAccountID("demo.expense.topstep.funded"),
        alphaFunded: TradingAccountID("demo.expense.alpha.funded")
    )

    static func bundle(now: Date = Date(), viewer: ProfileID = DemoCanonicalDataset.profileID) -> Bundle {
        let calendar = Calendar(identifier: .gregorian)
        var eastern = calendar
        eastern.timeZone = TradingReportPeriods.eastern.timeZone
        let today = eastern.startOfDay(for: now)
        guard eastern.date(byAdding: .month, value: -6, to: today) != nil else {
            return emptyBundle(viewer: viewer)
        }

        let accounts = previewAccounts(owner: viewer)
        var expenses: [PropFirmExpense] = []
        var payoutItems: [PayoutHistoryItem] = []
        var payoutFirmNames: [String: String] = [:]

        let firms: [(name: String, evalCost: Decimal, account: TradingAccountID)] = [
            ("Apex", 167, previewAccountIDs.apexEval),
            ("Topstep", 149, previewAccountIDs.topstepFunded),
            ("Alpha Futures", 99, previewAccountIDs.alphaFunded),
        ]

        let currentMonthStart = eastern.date(from: eastern.dateComponents([.year, .month], from: today)) ?? today
        for monthOffset in 0..<6 {
            guard let monthStart = eastern.date(byAdding: .month, value: monthOffset - 5, to: currentMonthStart) else {
                continue
            }
            for week in 0..<3 {
                let index = monthOffset * 3 + week
                let firm = firms[index % firms.count]
                let day = eastern.date(byAdding: .day, value: 4 + week * 9, to: monthStart) ?? monthStart
                guard day <= today else { continue }
                let dayKey = PropFirmExpenseMoney.dayString(from: day, calendar: eastern)
                expenses.append(
                    PropFirmExpense(
                        id: "demo-expense-eval-\(monthOffset)-\(week)",
                        propFirmName: firm.name,
                        expenseType: .evaluationPurchase,
                        costPerAccount: firm.evalCost,
                        quantity: 1,
                        totalCost: firm.evalCost,
                        datePaid: dayKey,
                        paymentLabel: "Card",
                        notes: "\(firm.name) 50K evaluation",
                        accountID: firm.account,
                        source: .manual,
                        trackerKind: .propFirm
                    )
                )
            }
        }

        expenses.append(
            PropFirmExpense(
                id: "demo-expense-reset-1",
                propFirmName: "Apex",
                expenseType: .resetFee,
                costPerAccount: 85,
                quantity: 1,
                totalCost: 85,
                datePaid: dayKey(offsetMonths: -4, day: 12, from: today, calendar: eastern),
                paymentLabel: "Card",
                notes: "Evaluation reset",
                accountID: previewAccountIDs.apexEval,
                source: .manual,
                trackerKind: .propFirm
            )
        )
        expenses.append(
            PropFirmExpense(
                id: "demo-expense-reset-2",
                propFirmName: "Topstep",
                expenseType: .resetFee,
                costPerAccount: 75,
                quantity: 1,
                totalCost: 75,
                datePaid: dayKey(offsetMonths: -2, day: 8, from: today, calendar: eastern),
                paymentLabel: "Card",
                accountID: previewAccountIDs.topstepFunded,
                source: .manual,
                trackerKind: .propFirm
            )
        )
        expenses.append(
            PropFirmExpense(
                id: "demo-expense-activation",
                propFirmName: "Alpha Futures",
                expenseType: .activationFee,
                costPerAccount: 149,
                quantity: 1,
                totalCost: 149,
                datePaid: dayKey(offsetMonths: -3, day: 20, from: today, calendar: eastern),
                paymentLabel: "Card",
                accountID: previewAccountIDs.alphaFunded,
                source: .manual,
                trackerKind: .propFirm
            )
        )

        let recurringStart = dayKey(offsetMonths: -5, day: 3, from: today, calendar: eastern)
        expenses.append(
            PropFirmExpense(
                id: "demo-expense-tradingview",
                propFirmName: "TradingView",
                expenseType: .subscriptionRenewal,
                costPerAccount: Decimal(string: "29.99")!,
                quantity: 1,
                totalCost: Decimal(string: "29.99")!,
                datePaid: recurringStart,
                paymentLabel: "Card",
                notes: "Plus plan",
                accountID: nil,
                source: .manual,
                trackerKind: .tradingTools,
                projectLabel: "Charts",
                customCategory: "Platform subscription",
                recurrence: .monthly
            )
        )
        expenses.append(
            PropFirmExpense(
                id: "demo-expense-market-data",
                propFirmName: "CME Bundle",
                expenseType: .subscriptionRenewal,
                costPerAccount: Decimal(string: "49.99")!,
                quantity: 1,
                totalCost: Decimal(string: "49.99")!,
                datePaid: recurringStart,
                paymentLabel: "Card",
                notes: "NQ/ES market data",
                accountID: nil,
                source: .manual,
                trackerKind: .propFirm,
                recurrence: .monthly
            )
        )
        expenses.append(
            PropFirmExpense(
                id: "demo-expense-platform",
                propFirmName: "Rithmic",
                expenseType: .subscriptionRenewal,
                costPerAccount: Decimal(string: "49.50")!,
                quantity: 1,
                totalCost: Decimal(string: "49.50")!,
                datePaid: dayKey(offsetMonths: -4, day: 10, from: today, calendar: eastern),
                paymentLabel: "Card",
                notes: "Platform connectivity",
                accountID: nil,
                source: .manual,
                trackerKind: .tradingTools,
                projectLabel: "Execution",
                customCategory: "Platform subscription",
                recurrence: .monthly
            )
        )
        expenses.append(
            PropFirmExpense(
                id: "demo-expense-equipment",
                propFirmName: "Apple",
                expenseType: .other,
                costPerAccount: 235,
                quantity: 1,
                totalCost: 235,
                datePaid: dayKey(offsetMonths: -5, day: 2, from: today, calendar: eastern),
                paymentLabel: "Card",
                notes: "Trading workstation accessories",
                accountID: nil,
                source: .manual,
                trackerKind: .business,
                projectLabel: "Equipment",
                customCategory: "Computer hardware"
            )
        )
        expenses.append(
            PropFirmExpense(
                id: "demo-expense-filing",
                propFirmName: "IL SOS",
                expenseType: .other,
                costPerAccount: Decimal(string: "380.75")!,
                quantity: 1,
                totalCost: Decimal(string: "380.75")!,
                datePaid: dayKey(offsetMonths: -3, day: 7, from: today, calendar: eastern),
                paymentLabel: "Card",
                source: .manual,
                trackerKind: .propFirm,
                recurrence: nil
            )
        )
        let payouts: [(firm: String, amount: Decimal, monthsAgo: Int, day: Int, account: TradingAccountID)] = [
            ("Apex", 1750, 5, 22, previewAccountIDs.apexEval),
            ("Topstep", 2000, 4, 14, previewAccountIDs.topstepFunded),
            ("Alpha Futures", 1500, 3, 9, previewAccountIDs.alphaFunded),
            ("Apex", 1750, 2, 26, previewAccountIDs.apexEval),
            ("Topstep", 1750, 1, 11, previewAccountIDs.topstepFunded),
        ]

        for (index, row) in payouts.enumerated() {
            let day = dayKey(offsetMonths: -row.monthsAgo, day: row.day, from: today, calendar: eastern)
            guard let date = PropFirmExpenseMoney.date(fromDay: day, calendar: eastern) else { continue }
            let itemID = "demo-payout-\(index)"
            payoutItems.append(
                PayoutHistoryItem(
                    id: itemID,
                    amount: row.amount,
                    date: date,
                    accountID: row.account,
                    ledgerEntryID: nil,
                    source: .fundedCycle,
                    note: "\(row.firm) funded payout"
                )
            )
            payoutFirmNames[itemID] = row.firm
        }

        let categories = ["Platform subscription", "Data feed", "Computer hardware", "Office supplies"]

        return Bundle(
            expenses: expenses.sorted { $0.datePaid > $1.datePaid },
            income: [],
            accounts: accounts,
            payoutItems: payoutItems.sorted { $0.date > $1.date },
            payoutFirmNames: payoutFirmNames,
            savedCategories: categories
        )
    }

    static func yearTotals(for bundle: Bundle, year: Int, now: Date = Date()) -> YearTotals {
        let through = PropFirmExpenseMoney.dayString(from: now)
        let expanded = ExpenseRecurrenceSchedule.expand(bundle.expenses, through: through)
        let start = String(format: "%04d-01-01", year)
        let end = String(format: "%04d-12-31", year)
        let yearRows = expanded.filter { $0.datePaid >= start && $0.datePaid <= end }
        let expenseTotal = yearRows.reduce(Decimal.zero) { $0 + $1.totalCost }
        let propTotal = yearRows
            .filter { $0.trackerKind == .propFirm }
            .reduce(Decimal.zero) { $0 + $1.totalCost }
        let payoutRows = bundle.payoutItems
            .filter { item in
                let day = PropFirmExpenseMoney.utcDayString(from: item.date)
                return day >= start && day <= end
            }
        let payoutTotal = payoutRows.reduce(Decimal.zero) { $0 + $1.amount }
        return YearTotals(
            expandedExpenseTotal: expenseTotal,
            propExpenseTotal: propTotal,
            payoutTotal: payoutTotal,
            net: payoutTotal - expenseTotal,
            deductibleEstimate: propTotal
        )
    }

    private static func emptyBundle(viewer: ProfileID) -> Bundle {
        Bundle(expenses: [], income: [], accounts: previewAccounts(owner: viewer), payoutItems: [], payoutFirmNames: [:], savedCategories: [])
    }

    private static func previewAccounts(owner: ProfileID) -> [TradingAccount] {
        [
            TradingAccount(
                id: previewAccountIDs.apexEval,
                ownerProfileID: owner,
                name: "Apex 50K Evaluation",
                category: .propFirm,
                mode: .evaluation,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "APX-PREV-1"
            ),
            TradingAccount(
                id: previewAccountIDs.topstepFunded,
                ownerProfileID: owner,
                name: "Topstep 50K Funded",
                category: .propFirm,
                mode: .funded,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "TS-PREV-1"
            ),
            TradingAccount(
                id: previewAccountIDs.alphaFunded,
                ownerProfileID: owner,
                name: "Alpha 50K Funded",
                category: .propFirm,
                mode: .funded,
                size: Money(amount: 50_000),
                isActive: true,
                canAddTrades: true,
                accountNumber: "AF-PREV-1"
            ),
        ]
    }

    private static func dayKey(offsetMonths: Int, day: Int, from: Date, calendar: Calendar) -> String {
        let monthAnchor = calendar.date(byAdding: .month, value: offsetMonths, to: from) ?? from
        var comps = calendar.dateComponents([.year, .month], from: monthAnchor)
        comps.day = min(day, 28)
        let date = calendar.date(from: comps) ?? monthAnchor
        return PropFirmExpenseMoney.dayString(from: date, calendar: calendar)
    }
}