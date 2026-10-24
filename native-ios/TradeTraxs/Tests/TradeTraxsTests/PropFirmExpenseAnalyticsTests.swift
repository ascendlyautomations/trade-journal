import XCTest
@testable import TradeTraxs

final class PropFirmExpenseAnalyticsTests: XCTestCase {
    func testMoneyMultiplyAndFormatStayOnCents() {
        let cost = PropFirmExpenseMoney.parse("19.99")
        XCTAssertEqual(cost, Decimal(string: "19.99"))
        let total = PropFirmExpenseMoney.total(cost: cost ?? 0, quantity: 3)
        XCTAssertEqual(total, Decimal(string: "59.97"))
        XCTAssertEqual(PropFirmExpenseMoney.plainDecimalString(total), "59.97")
        XCTAssertEqual(PropFirmExpenseMoney.format(Decimal(string: "-2.50") ?? 0), "-$2.50")
    }

    func testRecurringExpensesIncludeEveryDateSinceTheStart() {
        XCTAssertEqual(
            ExpenseRecurrenceSchedule.dates(from: "2026-10-01", recurrence: .weekly, through: "2026-10-15"),
            ["2026-10-01", "2026-10-08", "2026-10-15"]
        )
        XCTAssertEqual(
            ExpenseRecurrenceSchedule.dates(from: "2024-01-31", recurrence: .monthly, through: "2024-03-31"),
            ["2024-01-31", "2024-02-29", "2024-03-31"]
        )
        XCTAssertEqual(
            ExpenseRecurrenceSchedule.dates(from: "2026-12-01", recurrence: .monthly, through: "2026-11-01"),
            []
        )
    }

    func testNetProfitUsesExistingPayoutsAndGroupsFirms() {
        let rows = [
            sample(id: "1", firm: "Apex", type: .evaluationPurchase, cost: "19.99", quantity: 3, total: "59.97", day: "2026-10-01"),
            sample(id: "2", firm: "apex", type: .resetFee, cost: "100", quantity: 1, total: "100.00", day: "2026-09-15"),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23)) ?? .now
        let summary = PropFirmExpenseAnalyticsBuilder.summarize(
            expenses: rows,
            payouts: Decimal(string: "250.00") ?? 0,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(summary.totalSpent, Decimal(string: "159.97"))
        XCTAssertEqual(summary.totalAccountsPurchased, 4)
        XCTAssertEqual(summary.netProfit, Decimal(string: "90.03"))
        XCTAssertEqual(summary.byFirm.count, 1)
        XCTAssertEqual(summary.byCategory.map(\.id), ["evaluation_purchase", "reset_fee"])
        XCTAssertEqual(summary.monthly.count, 12)
        XCTAssertEqual(summary.monthly.first(where: { $0.monthKey == "2026-10" })?.total, Decimal(string: "59.97"))

        let filtered = PropFirmExpenseAnalyticsBuilder.filter(
            rows,
            with: PropFirmExpenseFilter(firmKey: "apex", category: .resetFee, fromDay: "2026-09-01", toDay: "2026-09-30")
        )
        XCTAssertEqual(filtered.map(\.id), ["2"])
    }

    func testAccountPurchaseTypeAndRepeatedIdentity() {
        XCTAssertEqual(
            PropFirmExpenseType.accountPurchaseType(category: .propFirm, mode: .evaluation),
            .evaluationPurchase
        )
        XCTAssertEqual(
            PropFirmExpenseType.accountPurchaseType(category: .propFirm, mode: .funded),
            .activationFee
        )
        XCTAssertNil(PropFirmExpenseType.accountPurchaseType(category: .personal, mode: .live))
        let expense = sample(
            id: "purchase",
            firm: "Topstep",
            type: .activationFee,
            cost: "149",
            quantity: 1,
            total: "149.00",
            day: "2026-10-23",
            source: .accountPurchase,
            accountID: TradingAccountID("account-1")
        )
        XCTAssertEqual(expense.accountPurchaseIdentity, "account_purchase:account-1")
    }

    func testValidationRejectsBlankCostAndFutureDate() {
        var draft = PropFirmExpenseDraft.empty(now: date("2026-10-23"))
        draft.propFirmName = "Apex"
        XCTAssertNotNil(PropFirmExpenseAnalyticsBuilder.validate(draft, today: "2026-10-23"))
        draft.costDigits = "10"
        draft.datePaid = date("2026-10-24")
        XCTAssertEqual(
            PropFirmExpenseAnalyticsBuilder.validate(draft, today: "2026-10-23"),
            "Purchase date cannot be in the future."
        )
    }

    func testTaxCsvKeepsCentsAndLimitsThePeriod() {
        var included = sample(
            id: "1",
            firm: "=Apex, Eval",
            type: .evaluationPurchase,
            cost: "19.99",
            quantity: 3,
            total: "59.97",
            day: "2026-02-01"
        )
        included.paymentLabel = "Visa, personal"
        let excluded = sample(
            id: "2",
            firm: "Topstep",
            type: .resetFee,
            cost: "100",
            quantity: 1,
            total: "100.00",
            day: "2025-12-31"
        )
        let csv = PropFirmExpenseTaxExport.csv(
            periodStart: "2026-01-01",
            periodEnd: "2026-12-31",
            expenses: [included, excluded],
            payouts: [
                .init(payoutDate: "2026-06-01", propFirmName: "Apex", amount: Decimal(string: "250.00") ?? 0),
                .init(payoutDate: "2025-11-01", propFirmName: "Old", amount: 10),
            ]
        )
        XCTAssertTrue(csv.contains("Total Recorded Expenses,59.97"))
        XCTAssertTrue(csv.contains("Total Recorded Payouts,250.00"))
        XCTAssertTrue(csv.contains("Net Payouts After Expenses,190.03"))
        XCTAssertTrue(csv.contains("Potentially Deductible Expenses (unverified estimate),59.97"))
        XCTAssertTrue(csv.contains("\"'=Apex, Eval\""))
        XCTAssertTrue(csv.contains("\"Visa, personal\""))
        XCTAssertTrue(csv.contains("19.99,3,59.97"))
        XCTAssertFalse(csv.contains("2025-12-31"))
        XCTAssertFalse(csv.contains("Topstep"))
        XCTAssertTrue(csv.contains("does not determine tax treatment"))
        XCTAssertEqual(
            PropFirmExpenseTaxExport.filename(start: "2026-01-01", end: "2026-12-31"),
            "tradetraxs-prop-firm-expenses-2026.csv"
        )
    }

    func testYearOverviewReservesPositiveNetAndLeavesUnmatchedPayoutsUnassigned() {
        let apex = TradingAccountID("acct")
        let other = TradingAccountID("other")
        let rows = [
            sample(
                id: "1",
                firm: "Apex",
                type: .evaluationPurchase,
                cost: "59.97",
                quantity: 1,
                total: "59.97",
                day: "2026-02-01",
                source: .accountPurchase,
                accountID: apex
            ),
            sample(id: "old", firm: "Topstep", type: .resetFee, cost: "100", quantity: 1, total: "100.00", day: "2025-12-31"),
        ]
        let overview = PropFirmYearOverviewBuilder.summarize(
            year: 2026,
            expenses: rows,
            payouts: [
                PropFirmOverviewPayout(payoutDate: "2026-06-01", accountID: apex, amount: Decimal(string: "250.00") ?? 0),
                PropFirmOverviewPayout(payoutDate: "2026-07-01", accountID: other, amount: Decimal(string: "100.00") ?? 0),
                PropFirmOverviewPayout(payoutDate: "2025-11-01", accountID: apex, amount: 50),
            ],
            reservePercent: 25
        )
        XCTAssertEqual(overview.expenses, Decimal(string: "59.97"))
        XCTAssertEqual(overview.payouts, Decimal(string: "350.00"))
        XCTAssertEqual(overview.net, Decimal(string: "290.03"))
        XCTAssertEqual(overview.reserve, Decimal(string: "72.51"))
        XCTAssertEqual(overview.mostProfitableFirmKey, "apex")
        XCTAssertEqual(overview.firms.first { $0.key == PropFirmYearOverviewBuilder.unassignedKey }?.payouts, Decimal(string: "100.00"))
        let named = PropFirmYearOverviewBuilder.summarize(
            year: 2026,
            expenses: rows,
            payouts: [
                PropFirmOverviewPayout(
                    payoutDate: "2026-08-01",
                    accountID: other,
                    amount: Decimal(string: "100.00") ?? 0,
                    accountName: "Alpha futures 150K"
                ),
            ],
            reservePercent: 25
        )
        XCTAssertEqual(named.firms.first { $0.key == "alpha futures" }?.payouts, Decimal(string: "100.00"))
        XCTAssertNil(named.firms.first { $0.key == PropFirmYearOverviewBuilder.unassignedKey })
        XCTAssertEqual(overview.months.first { $0.monthKey == "2026-02" }?.expenses, Decimal(string: "59.97"))
        XCTAssertEqual(PropFirmYearOverviewBuilder.firmName(accountID: other, expenses: rows), "Unassigned")
        let underwater = PropFirmYearOverviewBuilder.summarize(
            year: 2026,
            expenses: rows,
            payouts: [PropFirmOverviewPayout(payoutDate: "2026-03-01", accountID: apex, amount: 10)],
            reservePercent: 30
        )
        XCTAssertEqual(underwater.reserve, 0)
        XCTAssertEqual(underwater.firms.first { $0.key == "apex" }?.shortfall, Decimal(string: "49.97"))
        XCTAssertEqual(PropFirmYearOverviewBuilder.parsePercent("22.5"), Decimal(string: "22.5"))
        XCTAssertNil(PropFirmYearOverviewBuilder.parsePercent("0"))
        let assigned = PropFirmYearOverviewBuilder.summarize(
            year: 2026,
            expenses: [],
            payouts: [
                PropFirmOverviewPayout(
                    payoutDate: "2026-04-01",
                    accountID: other,
                    amount: 80,
                    assignedFirmName: "Apex"
                ),
            ],
            reservePercent: 25
        )
        XCTAssertEqual(assigned.firms.first?.label, "Apex")
        XCTAssertNil(assigned.firms.first { $0.key == PropFirmYearOverviewBuilder.unassignedKey })
    }

    private func sample(
        id: String,
        firm: String,
        type: PropFirmExpenseType,
        cost: String,
        quantity: Int,
        total: String,
        day: String,
        source: PropFirmExpenseSource = .manual,
        accountID: TradingAccountID? = nil
    ) -> PropFirmExpense {
        PropFirmExpense(
            id: id,
            propFirmName: firm,
            expenseType: type,
            costPerAccount: Decimal(string: cost) ?? 0,
            quantity: quantity,
            totalCost: Decimal(string: total) ?? 0,
            datePaid: day,
            paymentLabel: nil,
            notes: nil,
            accountID: accountID,
            source: source
        )
    }

    private func date(_ day: String) -> Date {
        PropFirmExpenseMoney.date(fromDay: day) ?? .now
    }
}
