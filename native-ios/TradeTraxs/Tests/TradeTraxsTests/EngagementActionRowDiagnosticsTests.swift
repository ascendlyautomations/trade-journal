import XCTest
@testable import TradeTraxs

final class EngagementActionRowDiagnosticsTests: XCTestCase {
    func testSharedActionRowMetricsAreStable() {
        XCTAssertEqual(EngagementActionRowMetrics.iconPointSize, 18)
        XCTAssertEqual(EngagementActionRowMetrics.rowHeight, 32)
        XCTAssertEqual(EngagementActionRowMetrics.actionContainerSide, 32)
    }
}
