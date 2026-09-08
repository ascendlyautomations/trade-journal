import XCTest
@testable import TradeTraxs

final class EngagementActionRowDiagnosticsTests: XCTestCase {
    func testSharedActionRowMetricsAreStable() {
        XCTAssertEqual(EngagementActionRowMetrics.iconPointSize, 17)
        XCTAssertEqual(EngagementActionRowMetrics.rowHeight, 32)
        XCTAssertEqual(EngagementActionRowMetrics.iconFrameSide, 22)
    }
}
