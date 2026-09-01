import XCTest

/// Rendered navigation integration tests — exercises the live tab shell and system Back.
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitesting-navigation-shell"]
        app.launch()
        try awaitAuthenticatedShell(timeout: 45)
    }

    /// Waits for the main tab shell, tapping Debug Continue if auth is still visible.
    private func awaitAuthenticatedShell(
        timeout: TimeInterval,
        expectsTradesRoot: Bool = false
    ) {
        let probe = app.otherElements["navigation.probe"]
        let calendar = app.buttons["dashboard.calendar"]
        let tradesHome = element("trades.home")
        let continueDebug = app.buttons["auth.continue"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if probe.waitForExistence(timeout: 1) {
                let value = probe.value as? String ?? ""
                if value.hasPrefix("tab:") {
                    if expectsTradesRoot {
                        if tradesHome.waitForExistence(timeout: 1) { return }
                        if element("settings.tradingAccounts").waitForExistence(timeout: 1) { return }
                    }
                    if calendar.waitForExistence(timeout: 1) {
                        return
                    }
                }
            }
            if continueDebug.exists, continueDebug.isHittable {
                continueDebug.tap()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        let probeValue = probe.value as? String ?? "missing"
        XCTFail(
            "Authenticated shell did not appear within \(timeout)s. Last probe: \(probeValue)"
        )
    }

    // MARK: - Flow A

    @MainActor
    func testFlowA_MessagesSettingsToolbarBack() throws {
        selectTab("Messages")
        tapWhenReady(element("messages.settings"))

        XCTAssertTrue(element("settings.home").waitForExistence(timeout: 8))
        assertProbe(contains: "tab:messages", "messages:settings(home)")

        tapSystemBack()
        XCTAssertTrue(element("messages.settings").waitForExistence(timeout: 8))
        assertProbe(contains: "tab:messages", "messages:")
        assertProbe(doesNotContain: "settings(home)")
    }

    // MARK: - Flow B

    @MainActor
    func testFlowB_MessagesSettingsNotificationsToolbarBackChain() throws {
        selectTab("Messages")
        tapWhenReady(element("messages.settings"))
        XCTAssertTrue(element("settings.home").waitForExistence(timeout: 8))

        tapWhenReady(element("settings.row.notifications"))
        XCTAssertTrue(element("settings.notifications").waitForExistence(timeout: 8))
        assertProbe(contains: "messages:settings(home),settings(notifications)")

        tapWhenReady(element("settings.notifications.category.messages"))
        XCTAssertTrue(element("settings.notifications.messages").waitForExistence(timeout: 8))
        assertProbe(contains: "settings(notifications-messages)")

        tapSystemBack()
        XCTAssertTrue(element("settings.notifications").waitForExistence(timeout: 8))

        tapSystemBack()
        XCTAssertTrue(element("settings.home").waitForExistence(timeout: 8))

        tapSystemBack()
        XCTAssertTrue(element("messages.settings").waitForExistence(timeout: 8))
        assertProbe(contains: "tab:messages", "messages:")
        assertProbe(doesNotContain: "settings(")
    }

    // MARK: - Flow C

    @MainActor
    func testFlowC_DashboardTradesToolbarBack() throws {
        relaunchApp(additionalArguments: ["-uitesting-navigation-start-trades"])
        XCTAssertTrue(element("trades.home").waitForExistence(timeout: 10))
        assertProbe(contains: "home:trades")

        tapSystemBack()
        XCTAssertTrue(app.buttons["dashboard.calendar"].waitForExistence(timeout: 8))
        assertProbe(contains: "home:", doesNotContainPathSegment: "trades")
    }

    // MARK: - Flow D

    @MainActor
    func testFlowD_DashboardTradesManageAccountsToolbarBackChain() throws {
        relaunchApp(additionalArguments: ["-uitesting-navigation-start-trades-manage-accounts"])
        XCTAssertTrue(element("settings.tradingAccounts").waitForExistence(timeout: 10))
        assertProbe(contains: "home:trades,settings(trading-accounts)")
        assertProbe(doesNotContain: "settings(home)")

        tapSystemBack()
        XCTAssertTrue(element("trades.home").waitForExistence(timeout: 10))
        assertProbe(contains: "home:trades")

        tapSystemBack()
        XCTAssertTrue(app.buttons["dashboard.calendar"].waitForExistence(timeout: 10))
        assertProbe(contains: "home:", doesNotContainPathSegment: "trades")
    }

    // MARK: - Flow E

    @MainActor
    func testFlowE_ProfileActivityNotificationSettingsToolbarBackChain() throws {
        selectTab("Home")
        tapWhenReady(app.buttons["dashboard.activity"])
        XCTAssertTrue(element("activity.home").waitForExistence(timeout: 8))
        assertProbe(contains: "tab:profile", "profile:activity")

        tapWhenReady(app.buttons["activity.menu"])
        tapWhenReady(app.buttons["Notification Settings"])
        XCTAssertTrue(element("settings.notifications").waitForExistence(timeout: 8))
        assertProbe(contains: "profile:activity,settings(notifications)")

        tapSystemBack()
        XCTAssertTrue(element("activity.home").waitForExistence(timeout: 8))
        assertProbe(contains: "profile:activity")

        tapSystemBack()
        XCTAssertTrue(element("profile.root.owner").waitForExistence(timeout: 8))
        assertProbe(matches: "profile:")
    }

    // MARK: - Tab isolation

    @MainActor
    func testOwnerAccountFilterDropdownCompactOverlayOnDashboard() throws {
        relaunchApp(additionalArguments: ["-uitesting-navigation-start-trades"])
        dismissAlertsIfNeeded()
        let account = accountFilterButton(identifier: "trades.account")
        XCTAssertTrue(element("trades.home").waitForExistence(timeout: 15), "Trades screen missing")
        XCTAssertTrue(account.waitForExistence(timeout: 45), "Trades account selector missing")
        account.tap()
        let dismissLayer = app.buttons["Dismiss account filter"]
        let panel = app.descendants(matching: .any)["ownerAccountFilter.dropdown.panel"]
        XCTAssertTrue(
            dismissLayer.waitForExistence(timeout: 5) || panel.waitForExistence(timeout: 1),
            "Compact dropdown overlay missing"
        )
        XCTAssertTrue(panel.waitForExistence(timeout: 1), "Compact dropdown panel missing")
        XCTAssertTrue(app.buttons["All Accounts"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Manage Accounts"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("trades.home").exists, "Trades screen should remain visible behind overlay")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Account filter compact overlay"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.92)).tap()
        let dismissed = !panel.waitForExistence(timeout: 0.5)
        if !dismissed {
            // Fallback: explicit dismiss control from the transparent capture layer.
            if dismissLayer.exists { dismissLayer.tap() }
        }
        XCTAssertFalse(panel.waitForExistence(timeout: 2), "Outside tap should dismiss dropdown")
    }

    private func dismissAlertsIfNeeded() {
        let deny = app.alerts.buttons["Don't Allow"]
        if deny.waitForExistence(timeout: 1) { deny.tap() }
    }

    @MainActor
    func testMessagesSettingsDoesNotMutateProfilePath() throws {
        selectTab("Messages")
        tapWhenReady(element("messages.settings"))
        XCTAssertTrue(element("settings.home").waitForExistence(timeout: 8))
        assertProbe(contains: "tab:messages", "messages:settings(home)")
        assertProbe(matches: "profile:")
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).element(boundBy: 0)
    }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab \(name)")
        tab.tap()
        let probe = app.otherElements["navigation.probe"]
        _ = probe.waitForExistence(timeout: 3)
    }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)")
        if !element.isHittable {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            element.tap()
        }
    }

    private func tapSystemBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 2), back.isHittable {
            back.tap()
            return
        }
        let labeledBack = app.navigationBars.buttons["Back"]
        XCTAssertTrue(labeledBack.waitForExistence(timeout: 2))
        labeledBack.tap()
    }

    private func relaunchApp(additionalArguments: [String] = []) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-uitesting-navigation-shell"] + additionalArguments
        app.launch()
        awaitAuthenticatedShell(
            timeout: 45,
            expectsTradesRoot: additionalArguments.contains(where: {
                $0.hasPrefix("-uitesting-navigation-start-trades")
            })
        )
    }

    private func openManageAccountsFromTrades() {
        let manage = app.buttons["Manage Accounts"]
        XCTAssertTrue(manage.waitForExistence(timeout: 8), "Manage Accounts menu item missing")
        manage.tap()
    }

    private func openManageAccountsFromDashboard() {
        let accountMenu = app.buttons["dashboard.account"]
        XCTAssertTrue(accountMenu.waitForExistence(timeout: 5))
        accountMenu.tap()
        let manage = app.buttons["Manage Accounts"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
    }

    private func accountFilterButton(identifier: String) -> XCUIElement {
        let byID = element(identifier)
        if byID.waitForExistence(timeout: 1) {
            return byID
        }
        return app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", identifier, "Account")
        ).element(boundBy: 0)
    }

    private func probeValue() -> String {
        let probe = app.otherElements["navigation.probe"]
        _ = probe.waitForExistence(timeout: 2)
        return probe.value as? String ?? ""
    }

    private func assertProbe(contains substring: String, file: StaticString = #filePath, line: UInt = #line) {
        let value = probeValue()
        XCTAssertTrue(value.contains(substring), "Expected probe to contain '\(substring)' but got '\(value)'", file: file, line: line)
    }

    private func assertProbe(doesNotContain substring: String, file: StaticString = #filePath, line: UInt = #line) {
        let value = probeValue()
        XCTAssertFalse(value.contains(substring), "Expected probe to exclude '\(substring)' but got '\(value)'", file: file, line: line)
    }

    private func assertProbe(
        contains: String,
        doesNotContainPathSegment segment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertProbe(contains: contains, file: file, line: line)
        let value = probeValue()
        if let homeRange = value.range(of: "home:") {
            let homeSegment = String(value[homeRange.upperBound...])
            let end = homeSegment.firstIndex(of: "|") ?? homeSegment.endIndex
            let homePath = String(homeSegment[..<end])
            XCTAssertFalse(homePath.contains(segment), "Home path '\(homePath)' should not contain '\(segment)'", file: file, line: line)
        }
    }

    private func assertProbe(
        contains first: String,
        _ second: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertProbe(contains: first, file: file, line: line)
        assertProbe(contains: second, file: file, line: line)
    }

    private func assertProbe(
        matches profilePrefix: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let value = probeValue()
        if let range = value.range(of: "profile:") {
            let tail = String(value[range.lowerBound...])
            let end = tail.firstIndex(of: "|") ?? tail.endIndex
            let profilePath = String(tail[..<end])
            XCTAssertEqual(profilePath, profilePrefix, file: file, line: line)
        } else {
            XCTFail("Missing profile segment in probe '\(value)'", file: file, line: line)
        }
    }
}
