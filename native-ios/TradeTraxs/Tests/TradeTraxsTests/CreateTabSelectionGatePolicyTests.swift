import XCTest
import UIKit
@testable import TradeTraxs

final class CreateTabSelectionGatePolicyTests: XCTestCase {
    func testAllowsCreateShieldWhenTabBarVisible() {
        let tabBar = UITabBar(frame: CGRect(x: 0, y: 0, width: 390, height: 49))
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        host.addSubview(tabBar)
        tabBar.frame = CGRect(x: 0, y: 795, width: 390, height: 49)
        let window = UIWindow(frame: host.bounds)
        window.addSubview(host)
        window.makeKeyAndVisible()

        XCTAssertTrue(
            CreateTabSelectionGatePolicy.allowsCreateShield(tabBar: tabBar, tabBarController: nil)
        )
    }

    func testRejectsCreateShieldWhenTabBarHidden() {
        let tabBar = UITabBar(frame: CGRect(x: 0, y: 0, width: 390, height: 49))
        tabBar.isHidden = true
        XCTAssertFalse(
            CreateTabSelectionGatePolicy.allowsCreateShield(tabBar: tabBar, tabBarController: nil)
        )
    }

    func testRejectsCreateShieldWhenTabBarFullyTransparent() {
        let tabBar = UITabBar(frame: CGRect(x: 0, y: 0, width: 390, height: 49))
        tabBar.alpha = 0
        XCTAssertFalse(
            CreateTabSelectionGatePolicy.allowsCreateShield(tabBar: tabBar, tabBarController: nil)
        )
    }

    func testRejectsCreateShieldWhenTabBarOffscreenInController() {
        let controller = UITabBarController()
        let host = UIViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.addChild(host)
        controller.view.addSubview(host.view)
        host.didMove(toParent: controller)

        let tabBar = controller.tabBar
        tabBar.frame = CGRect(x: 0, y: 844, width: 390, height: 49)
        let window = UIWindow(frame: controller.view.bounds)
        window.addSubview(controller.view)
        window.makeKeyAndVisible()

        XCTAssertFalse(
            CreateTabSelectionGatePolicy.allowsCreateShield(
                tabBar: tabBar,
                tabBarController: controller
            )
        )
    }
}
