import XCTest
@testable import TradeTraxs

final class AdminExperienceTests: XCTestCase {
    func testAdminSettingsRouteUsesEmptyNavigationTitle() {
        XCTAssertEqual(SettingsRoute.admin.title, "")
    }

    func testAdminUserDirectoryDefaultPageSizeMatchesWeb() {
        XCTAssertEqual(AdminUserDirectoryQuery.defaultPageSize, 20)
    }
}
