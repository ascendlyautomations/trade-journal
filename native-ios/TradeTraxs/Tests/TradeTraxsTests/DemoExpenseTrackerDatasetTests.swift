import XCTest
@testable import TradeTraxs

final class DemoExpenseTrackerDatasetTests: XCTestCase {
    private let targetPayouts = Decimal(string: "8750.00")!
    private let targetExpenses = Decimal(string: "4125.00")!
    private let targetNet = Decimal(string: "4625.00")!
    private let targetDeductions = Decimal(string: "3480.00")!
    private let tolerance = Decimal(string: "120.00")!

    func testSampleDatasetTotalsStayNearTargets() {
        let now = Date()
        let bundle = DemoExpenseTrackerDataset.bundle(now: now)
        let year = Calendar.current.component(.year, from: now)
        let totals = DemoExpenseTrackerDataset.yearTotals(for: bundle, year: year, now: now)

        XCTAssertEqual(totals.payoutTotal, targetPayouts)
        assertClose(totals.expandedExpenseTotal, targetExpenses)
        assertClose(totals.net, targetNet)
        assertClose(totals.deductibleEstimate, targetDeductions)
        XCTAssertGreaterThan(bundle.expenses.count, 24, "expected ~6 months of activity")
        XCTAssertEqual(bundle.payoutItems.count, 5)
    }

    private func assertClose(_ value: Decimal, _ target: Decimal, file: StaticString = #file, line: UInt = #line) {
        let delta = (value - target).magnitude
        XCTAssertLessThanOrEqual(
            delta,
            tolerance,
            "expected \(target), got \(value) (delta \(delta))",
            file: file,
            line: line
        )
    }
}