import XCTest
@testable import TradeTraxs

final class CreateTabGateNavigationPolicyTests: XCTestCase {
    func testDMThreadDisablesCreateShield() {
        var paths = NavigationPathStore()
        paths.messages = [.thread(ConversationID("dm-1"))]
        XCTAssertFalse(
            CreateTabGateNavigationPolicy.shouldAllowCreateTabShield(
                selectedTab: .messages,
                paths: paths
            )
        )
    }

    func testMessagesInboxAllowsCreateShield() {
        let paths = NavigationPathStore()
        XCTAssertTrue(
            CreateTabGateNavigationPolicy.shouldAllowCreateTabShield(
                selectedTab: .messages,
                paths: paths
            )
        )
    }
}
