import XCTest

/// Real-app Demo Mode walk. Starts on Sign In, enters Explore as Guest, and opens
/// the core product surfaces a prospective user would tap.
final class DemoModeWalkUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitesting-reset-auth"]
        addUIInterruptionMonitor(withDescription: "system") { alert in
            let labels = ["Don’t Allow", "Don't Allow", "Not Now", "Cancel", "OK"]
            for label in labels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
    }

    @MainActor
    func testProspectiveUserCanExploreDemoWithoutAuthFailures() {
        let deadline = Date().addingTimeInterval(50)
        var enteredDemo = false
        while Date() < deadline {
            let explore = element("auth.exploreDemo")
            if explore.exists {
                if explore.isHittable {
                    explore.tap()
                } else {
                    explore.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                enteredDemo = true
                break
            }
            let signOut = element("auth.validation.signOut")
            if signOut.exists {
                if signOut.isHittable {
                    signOut.tap()
                } else {
                    signOut.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        if !enteredDemo {
            let visible = app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label).joined(separator: " | ")
            XCTFail("Sign In did not show Explore as Guest. Visible: \(visible)")
            return
        }

        XCTAssertTrue(element("dashboard.home").waitForExistence(timeout: 25))
        XCTAssertTrue(element("demo.leave").waitForExistence(timeout: 8))
        assertSurfaceIsUsable("dashboard")

        open("dashboard.calendar", expecting: "calendar.home", name: "calendar")
        goBack()
        open("dashboard.trades", label: "Trades", expecting: "trades.home", name: "trades")
        goBack()
        open("dashboard.reports", label: "Reports", expecting: "reports.home", name: "reports")
        if element("reports.card.monthly_last").waitForExistence(timeout: 6) {
            element("reports.card.monthly_last").tap()
            XCTAssertTrue(element("reports.detail").waitForExistence(timeout: 10), "monthly report detail")
            assertSurfaceIsUsable("report detail")
            goBack()
        }
        goBack()
        open("dashboard.withdrawals", label: "Withdrawals", expecting: "withdrawals.home", name: "withdrawals")
        goBack()
        open("dashboard.activity", expecting: "activity.home", name: "activity")
        goBack()

        selectTab("Feed")
        XCTAssertTrue(element("feed.home").waitForExistence(timeout: 12))
        assertSurfaceIsUsable("feed")
        if element("feed.explore").waitForExistence(timeout: 4) {
            element("feed.explore").tap()
            XCTAssertTrue(element("explore.home").waitForExistence(timeout: 12))
            assertSurfaceIsUsable("explore")
            goBack()
        }
        if element("feed.rooms").waitForExistence(timeout: 4) {
            element("feed.rooms").tap()
            XCTAssertTrue(element("tradeRooms.list").waitForExistence(timeout: 12))
            assertSurfaceIsUsable("trade rooms")
            goBack()
        }

        selectTab("Messages")
        XCTAssertTrue(element("messages.settings").waitForExistence(timeout: 12))
        assertSurfaceIsUsable("messages")
        let sarah = app.staticTexts["Sarah Chen"]
        if sarah.waitForExistence(timeout: 6) {
            sarah.tap()
            XCTAssertTrue(element("conversation.messageList").waitForExistence(timeout: 10))
            assertSurfaceIsUsable("conversation")
            goBack()
        }

        selectTab("Profile")
        XCTAssertTrue(element("profile.displayName").waitForExistence(timeout: 12))
        assertSurfaceIsUsable("profile")
        element("profile.toolbar.settings").tap()
        XCTAssertTrue(element("settings.home").waitForExistence(timeout: 10))
        assertSurfaceIsUsable("settings")
        element("settings.row.account").tap()
        XCTAssertTrue(element("settings.account").waitForExistence(timeout: 10))
        XCTAssertFalse(element("settings.account.downloadData").exists)
        XCTAssertFalse(app.staticTexts["Delete Account"].exists)
        XCTAssertFalse(app.staticTexts["Log Out"].exists)
        assertSurfaceIsUsable("settings account")
        goBack()
        if element("settings.row.vault").waitForExistence(timeout: 4) {
            element("settings.row.vault").tap()
            XCTAssertTrue(element("vault.home").waitForExistence(timeout: 10))
            assertSurfaceIsUsable("vault")
            goBack()
        }
        if element("settings.row.trading-accounts").waitForExistence(timeout: 4) {
            element("settings.row.trading-accounts").tap()
            XCTAssertTrue(element("settings.tradingAccounts").waitForExistence(timeout: 10))
            XCTAssertFalse(element("settings.tradingAccounts.brokerIntegrations").exists)
            XCTAssertFalse(element("manageAccounts.add").exists)
            assertSurfaceIsUsable("trading accounts")
            goBack()
        }

        element("demo.leave").tap()
        let exploreAgain = element("auth.exploreDemo")
        XCTAssertTrue(exploreAgain.waitForExistence(timeout: 15), "Exit Demo should return to Sign In")
        exploreAgain.tap()
        XCTAssertTrue(element("dashboard.home").waitForExistence(timeout: 20))
        XCTAssertTrue(element("dashboard.equity").waitForExistence(timeout: 15), "Demo should reload after re-entry")
        assertSurfaceIsUsable("demo re-entry")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "Missing tab \(name)")
        tab.tap()
    }

    private func open(_ control: String, label: String? = nil, expecting destination: String, name: String) {
        var button = element(control)
        if !button.waitForExistence(timeout: 8), let label {
            button = app.buttons[label]
        }
        if !button.waitForExistence(timeout: 12) {
            let skeleton = element("dashboard.skeleton").exists
            let home = element("dashboard.home").exists
            let equity = element("dashboard.equity").exists
            let filters = element("dashboard.filters").exists
            let empty = app.staticTexts["No trades yet"].exists
            let title = app.navigationBars.firstMatch.identifier
            XCTFail("Missing \(control). skeleton=\(skeleton) home=\(home) equity=\(equity) filters=\(filters) empty=\(empty) nav=\(title)")
            return
        }
        if button.isHittable {
            button.tap()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(element(destination).waitForExistence(timeout: 15), "\(name) did not open")
        assertSurfaceIsUsable(name)
    }

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 3), back.isHittable {
            back.tap()
            return
        }
        app.navigationBars.buttons["Back"].tap()
    }

    private func assertSurfaceIsUsable(_ name: String) {
        let blocked = [
            "Sign in to continue.",
            "Sign in to view your account.",
            "Unable to Contact Server",
            "Failed to Load",
            "sessionMissing",
        ]
        for phrase in blocked {
            XCTAssertFalse(
                app.staticTexts[phrase].exists,
                "\(name) showed \(phrase)"
            )
        }
    }
}
