import SwiftUI
import XCTest
@testable import TradeTraxs

@MainActor
final class ContextualTourTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var progress: ContextualTourProgressStore!
    private let cutoff = ContextualTourLaunch.accountCreatedAtCutoff
    private let viewerID = "11111111-1111-1111-1111-111111111111"

    override func setUp() {
        super.setUp()
        suiteName = "ContextualTourTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        progress = ContextualTourProgressStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        progress = nil
        super.tearDown()
    }

    func testUserACompletionDoesNotAffectUserB() {
        progress.dismiss(.dashboard, version: 1, userID: "user-a")
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-b"), 0)
        XCTAssertNotEqual(
            ContextualTourProgressStore.storageKey(userID: "user-a"),
            ContextualTourProgressStore.storageKey(userID: "user-b")
        )
    }

    func testSkipPersistsDashboardVersionOne() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        presentCurrentStep(coordinator)
        coordinator.skip()

        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
        XCTAssertFalse(coordinator.isPresenting)
        arm(coordinator, createdAt: afterCutoff)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testGotItPersistsDashboardVersionOne() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        for _ in 0..<ContextualTourCatalog.dashboard.informationalStepCount - 1 {
            presentCurrentStep(coordinator)
            coordinator.advance()
            if let surface = coordinator.navigationRequest {
                coordinator.syncShell(
                    userID: "user-a",
                    createdAt: afterCutoff,
                    gates: gates(for: surface)
                )
            }
        }
        presentCurrentStep(coordinator)
        XCTAssertTrue(coordinator.isFinalStep)
        coordinator.completeTour(configureTradingRules: false)

        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
        XCTAssertFalse(coordinator.isPresenting)
    }

    func testRelaunchReadsDismissedVersion() {
        progress.dismiss(.dashboard, version: 1, userID: "user-a")
        let reloaded = ContextualTourProgressStore(defaults: defaults)
        XCTAssertEqual(reloaded.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
        XCTAssertFalse(
            ContextualTourEligibility.shouldAutomaticallyPresent(
                createdAt: afterCutoff,
                cutoff: cutoff,
                dismissedVersion: reloaded.dismissedVersion(for: .dashboard, userID: "user-a"),
                tourVersion: 1
            )
        )
    }

    func testLogoutDoesNotEraseCompletion() {
        progress.dismiss(.dashboard, version: 1, userID: "user-a")
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        coordinator.resetForSessionBoundary()

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
        let reloaded = ContextualTourProgressStore(defaults: defaults)
        XCTAssertEqual(reloaded.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
    }

    func testPreCutoffAccountIsGrandfathered() {
        XCTAssertFalse(
            ContextualTourEligibility.shouldAutomaticallyPresent(
                createdAt: beforeCutoff,
                cutoff: cutoff,
                dismissedVersion: 0,
                tourVersion: 1
            )
        )
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: beforeCutoff)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)
    }

    func testZeroTradesStartsTourWhenHomeShellIsReady() {
        let coordinator = makeCoordinator()
        coordinator.syncShell(
            userID: "user-a",
            createdAt: afterCutoff,
            gates: ContextualTourGates(homeRootActive: true, sceneActive: true, unobstructed: true)
        )
        XCTAssertEqual(coordinator.phase, .preparing)
        XCTAssertFalse(coordinator.showsOverlay)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)
    }

    func testNextWalksEveryDashboardStepAndDismissesOnlyOnGotIt() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        let definition = ContextualTourCatalog.dashboard
        let informational = definition.steps.filter(\.role.countsTowardProgress)
        XCTAssertEqual(definition.informationalStepCount, informational.count)
        XCTAssertEqual(informational.map(\.title), [
            "Home tab — Your Dashboard",
            "Accounts & Timeframe",
            "Trading Performance",
            "Your Trade Journal",
            "Performance Reports",
            "Withdrawals & Expenses",
            "Trading Calendar",
            "Feed tab — Trading Community",
            "Feed Filters",
            "Trade Rooms",
            "Explore",
            "Create tab — Create & Journal",
            "Messages tab — Messages",
            "Profile tab — Your Profile",
            "Profile header — Your Trading Identity",
            "Your Trade Room",
            "Settings button — Settings",
            "Appearance",
            "Trading Rules",
            "Trading Rules",
        ])
        XCTAssertEqual(definition.steps.filter { $0.role == .sectionContinue }.count, 0)
        XCTAssertFalse(informational.contains { $0.title == "Understand your trading" })

        for index in informational.indices {
            let step = informational[index]
            if coordinator.phase == .preparing {
                let surface = coordinator.navigationRequest ?? step.surface
                coordinator.syncShell(
                    userID: "user-a",
                    createdAt: afterCutoff,
                    gates: gates(for: surface)
                )
                if coordinator.phase == .preparing {
                    presentCurrentStep(coordinator)
                }
            }
            XCTAssertEqual(coordinator.phase, .presenting, step.title)
            XCTAssertEqual(coordinator.currentStep?.title, step.title)
            XCTAssertEqual(coordinator.visibleStep?.title, step.title)
            XCTAssertEqual(coordinator.progressLabel, "\(index + 1) of \(informational.count)")
            XCTAssertTrue(coordinator.showsExplanationCard)
            XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)
            if index == informational.count - 1 {
                XCTAssertEqual(step.role, .tradingRulesPrompt)
                XCTAssertTrue(coordinator.isFinalStep)
                coordinator.completeTour(configureTradingRules: false)
                XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
                XCTAssertFalse(coordinator.isPresenting)
                XCTAssertFalse(coordinator.showsOverlay)
                XCTAssertNil(coordinator.navigationRequest)
            } else {
                coordinator.advance()
                XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)
                XCTAssertFalse(coordinator.showsOverlay)
            }
        }
    }

    func testExitTourPersistsCompletionAndReplayDoesNotResetIt() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        presentCurrentStep(coordinator)
        coordinator.exitTour()

        XCTAssertEqual(
            coordinator.exitNotice,
            "You can restart the App Walkthrough anytime from Settings."
        )
        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertNil(coordinator.navigationRequest)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)

        coordinator.beginReplay()
        XCTAssertEqual(coordinator.phase, .preparing)
        XCTAssertEqual(coordinator.currentStep?.title, "Home tab — Your Dashboard")
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
    }

    func testOffscreenNextStepScrollsAndThenPresents() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        presentCurrentStep(coordinator)
        coordinator.advance()
        presentCurrentStep(coordinator)
        coordinator.advance()
        XCTAssertEqual(coordinator.phase, .preparing)
        XCTAssertFalse(coordinator.showsOverlay)
        XCTAssertEqual(coordinator.visibleStep?.title, "Trading Performance")

        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let hidden = CGRect(x: 16, y: 1200, width: 350, height: 220)
        let revision = coordinator.stepRevision
        coordinator.noteMeasuredFrame(hidden, viewport: viewport, topInset: 59, bottomInset: 83, revision: revision)
        XCTAssertEqual(coordinator.scrollTarget, .dashboardPerformance)
        XCTAssertEqual(coordinator.phase, .preparing)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)

        let visible = CGRect(x: 16, y: 180, width: 350, height: 220)
        coordinator.noteMeasuredFrame(visible, viewport: viewport, topInset: 59, bottomInset: 83, revision: revision)
        coordinator.noteMeasuredFrame(
            visible,
            viewport: viewport,
            topInset: 59,
            bottomInset: 83,
            revision: revision
        )
        XCTAssertTrue(coordinator.isPresenting)
        XCTAssertEqual(coordinator.currentStep?.title, "Trading Performance")
        XCTAssertNil(coordinator.scrollTarget)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)
    }

    func testMissingTargetScrollsAndStaysMeasuringWithoutSkipping() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        presentCurrentStep(coordinator)
        coordinator.advance()
        XCTAssertEqual(coordinator.currentStep?.target, .dashboardPerformance)
        XCTAssertEqual(coordinator.phase, .preparing)
        XCTAssertEqual(coordinator.scrollTarget, .dashboardPerformance)
        XCTAssertEqual(coordinator.stepIndex, 2)
        XCTAssertFalse(coordinator.showsOverlay)
        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)
    }

    func testPostCutoffAccountIsEligible() {
        XCTAssertTrue(
            ContextualTourEligibility.isAccountEligible(createdAt: cutoff, cutoff: cutoff)
        )
        XCTAssertTrue(
            ContextualTourEligibility.shouldAutomaticallyPresent(
                createdAt: afterCutoff,
                cutoff: cutoff,
                dismissedVersion: 0,
                tourVersion: ContextualTourCatalog.dashboard.version
            )
        )
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        XCTAssertEqual(coordinator.phase, .preparing)
    }

    func testMissingCreatedAtMapsToEpochAndIsNotEligible() throws {
        let applied = try mapSession(createdAt: nil)
        XCTAssertEqual(applied.profile.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertFalse(
            ContextualTourEligibility.isAccountEligible(
                createdAt: applied.profile.createdAt,
                cutoff: cutoff
            )
        )
        XCTAssertGreaterThan(abs(applied.profile.createdAt.timeIntervalSinceNow), 60)
    }

    func testCurrentTestAccountCreatedAtIsEligibleOnlyAfterTemporaryCutoff() throws {
        let raw = "2026-09-25T01:29:13.887Z"
        let applied = try mapSession(createdAt: raw)
        let expected = try XCTUnwrap(ISO8601.date(from: raw))
        XCTAssertEqual(
            applied.profile.createdAt.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertNotEqual(applied.profile.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertTrue(
            ContextualTourEligibility.isAccountEligible(
                createdAt: applied.profile.createdAt,
                cutoff: cutoff
            )
        )
        let production = try XCTUnwrap(
            ISO8601.date(from: ContextualTourLaunch.productionAccountCreatedAtCutoffISO8601)
        )
        XCTAssertEqual(ContextualTourLaunch.productionAccountCreatedAtCutoffISO8601, "2026-09-23T00:00:00Z")
        XCTAssertTrue(
            ContextualTourEligibility.isAccountEligible(
                createdAt: applied.profile.createdAt,
                cutoff: production
            )
        )
        XCTAssertLessThan(cutoff, expected)
    }

    func testSessionCreatedAtMapsToProfile() throws {
        let raw = "2026-10-02T15:04:05.000Z"
        let applied = try mapSession(createdAt: raw)
        let expected = try XCTUnwrap(ISO8601.date(from: raw))
        XCTAssertEqual(applied.profile.createdAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(
            ContextualTourEligibility.isAccountEligible(
                createdAt: applied.profile.createdAt,
                cutoff: cutoff
            )
        )
    }

    func testUnavailableTargetStaysMeasuringWithoutAutoSkip() {
        XCTAssertEqual(
            ContextualTourGeometry.resolve(frame: nil, previous: nil, elapsed: 2),
            .skip
        )
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        XCTAssertEqual(coordinator.phase, .preparing)
        XCTAssertEqual(coordinator.stepIndex, 0)
        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)
    }

    func testBelowFoldTargetRequestsScrollInsteadOfGuessing() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        let hidden = CGRect(x: 16, y: 1400, width: 200, height: 120)
        coordinator.noteMeasuredFrame(
            hidden,
            viewport: CGRect(x: 0, y: 0, width: 390, height: 844),
            topInset: 100,
            bottomInset: 83,
            revision: coordinator.stepRevision
        )
        XCTAssertEqual(coordinator.scrollTarget, .dashboardAccountAndDates)
        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertEqual(coordinator.spotlightFrame, .zero)
    }

    func testInterruptedTourDoesNotMarkDismissed() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        presentCurrentStep(coordinator)
        XCTAssertTrue(coordinator.isPresenting)

        coordinator.syncShell(
            userID: "user-a",
            createdAt: afterCutoff,
            gates: ContextualTourGates(homeRootActive: false, sceneActive: true, unobstructed: true)
        )
        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 0)

        coordinator.beginReplay()
        XCTAssertEqual(coordinator.phase, .preparing)
    }

    func testVersionIncrementMakesOnlyThatTourEligibleAgain() {
        progress.dismiss(.dashboard, version: 1, userID: "user-a")
        progress.setRecord(1, tourKey: "feed", userID: "user-a")

        XCTAssertFalse(
            ContextualTourEligibility.shouldAutomaticallyPresent(
                createdAt: afterCutoff,
                cutoff: cutoff,
                dismissedVersion: progress.dismissedVersion(for: .dashboard, userID: "user-a"),
                tourVersion: 1
            )
        )
        XCTAssertTrue(
            ContextualTourEligibility.shouldAutomaticallyPresent(
                createdAt: afterCutoff,
                cutoff: cutoff,
                dismissedVersion: progress.dismissedVersion(for: .dashboard, userID: "user-a"),
                tourVersion: 2
            )
        )
        XCTAssertEqual(progress.dismissedVersion(forTourKey: "feed", userID: "user-a"), 1)
        XCTAssertEqual(ContextualTourCatalog.dashboard.version, 1)
    }

    func testReplayDoesNotRewriteStoredCompletion() {
        progress.dismiss(.dashboard, version: 1, userID: "user-a")
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: beforeCutoff)
        XCTAssertEqual(coordinator.phase, .idle)
        coordinator.beginReplay()
        XCTAssertEqual(coordinator.phase, .preparing)
        presentCurrentStep(coordinator)
        coordinator.skip()
        XCTAssertEqual(progress.dismissedVersion(for: .dashboard, userID: "user-a"), 1)
    }

    func testReduceMotionCrossfadesInsteadOfMovingTheSpotlight() {
        XCTAssertTrue(ContextualTourMotion.prefersCrossfade(reduceMotion: true))
        XCTAssertNil(ContextualTourMotion.spotlightAnimation(reduceMotion: true))
        XCTAssertFalse(ContextualTourMotion.prefersCrossfade(reduceMotion: false))
        XCTAssertNotNil(ContextualTourMotion.spotlightAnimation(reduceMotion: false))
    }

    func testCardAnchorsBelowSpotlightWhenSpaceAllows() {
        let size = CGSize(width: 390, height: 844)
        let status: CGFloat = 59
        let bottom: CGFloat = 83
        let cardHeight: CGFloat = 180
        let hole = CGRect(x: 16, y: 180, width: 360, height: 220)
        let top = ContextualTourCardPlacement.proposedTop(
            hole: hole,
            cardHeight: cardHeight,
            containerSize: size,
            statusBarInset: status,
            bottomInset: bottom
        )
        XCTAssertGreaterThanOrEqual(top, hole.maxY + ContextualTourCardPlacement.gap - 0.5)
    }

    func testCardAnchorsAboveSpotlightWhenBelowDoesNotFit() {
        let size = CGSize(width: 390, height: 844)
        let status: CGFloat = 59
        let bottom: CGFloat = 83
        let cardHeight: CGFloat = 180
        let hole = CGRect(x: 16, y: 620, width: 360, height: 72)
        let top = ContextualTourCardPlacement.proposedTop(
            hole: hole,
            cardHeight: cardHeight,
            containerSize: size,
            statusBarInset: status,
            bottomInset: bottom
        )
        XCTAssertLessThanOrEqual(top + cardHeight, hole.minY - ContextualTourCardPlacement.gap + 0.5)
    }

    func testNeedsScrollStopsWhenSpotlightIsRenderable() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let equityBlock = CGRect(x: 16, y: 160, width: 358, height: 320)
        XCTAssertFalse(
            ContextualTourGeometry.needsScroll(
                frame: equityBlock,
                viewport: viewport,
                topInset: 59,
                bottomInset: 83
            )
        )
    }

    func testDashboardPerformanceUsesTopScrollAnchor() {
        XCTAssertEqual(
            ContextualTourGeometry.scrollAnchor(for: .dashboardPerformance),
            .top
        )
        XCTAssertEqual(
            ContextualTourGeometry.scrollAnchor(for: .dashboardAccountAndDates),
            UnitPoint(x: 0.5, y: 0.14)
        )
    }

    func testSettingsTourScrollAnchorsAndMeasurementInset() {
        XCTAssertEqual(
            ContextualTourGeometry.scrollAnchor(for: .settingsAppearance),
            .center
        )
        XCTAssertEqual(
            ContextualTourGeometry.scrollAnchor(for: .settingsTradingRules),
            .center
        )
        XCTAssertEqual(
            ContextualTourGeometry.measurementTopInset(for: .settingsAppearance),
            ContextualTourCardPlacement.navigationClearance
        )
        XCTAssertEqual(ContextualTourGeometry.measurementTopInset(for: .dashboardTrades), 0)
    }

    func testSettingsAppearanceStepRequiresScrollWhenBelowFold() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let row = CGRect(x: 16, y: 720, width: 358, height: 52)
        let topInset: CGFloat = 59 + ContextualTourCardPlacement.navigationClearance
        XCTAssertTrue(
            ContextualTourGeometry.needsScroll(
                frame: row,
                viewport: viewport,
                topInset: topInset,
                bottomInset: 83
            )
        )
    }

    func testSpotlightRejectsAFullScreenFrame() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let control = CGRect(x: 16, y: 140, width: 240, height: 48)
        XCTAssertTrue(ContextualTourGeometry.isRenderableSpotlight(control, in: viewport))
        let belowFold = CGRect(x: 16, y: 1200, width: 240, height: 48)
        XCTAssertTrue(ContextualTourGeometry.isMeasurableTarget(belowFold, in: viewport))
        XCTAssertFalse(ContextualTourGeometry.isRenderableSpotlight(belowFold, in: viewport))
        XCTAssertFalse(
            ContextualTourGeometry.isRenderableSpotlight(viewport, in: viewport)
        )
        XCTAssertFalse(
            ContextualTourGeometry.isRenderableSpotlight(
                CGRect(x: 0, y: 0, width: 0, height: 40),
                in: viewport
            )
        )
    }

    func testPinsFeedFilterBarOnlyDuringFeedFiltersStep() {
        let coordinator = makeCoordinator()
        arm(coordinator, createdAt: afterCutoff)
        XCTAssertFalse(coordinator.pinsFeedFilterBar)

        coordinator.syncShell(
            userID: "user-a",
            createdAt: afterCutoff,
            gates: gates(for: .feed)
        )
        let feedFiltersIndex = ContextualTourCatalog.dashboard.steps.firstIndex {
            $0.target == .feedContentFilters
        }
        XCTAssertNotNil(feedFiltersIndex)
        while coordinator.stepIndex < feedFiltersIndex! {
            presentCurrentStep(coordinator)
            coordinator.advance()
            if let surface = coordinator.navigationRequest {
                coordinator.syncShell(
                    userID: "user-a",
                    createdAt: afterCutoff,
                    gates: gates(for: surface)
                )
            }
        }
        presentCurrentStep(coordinator)
        XCTAssertEqual(coordinator.currentStep?.target, .feedContentFilters)
        XCTAssertTrue(coordinator.pinsFeedFilterBar)

        coordinator.advance()
        XCTAssertFalse(coordinator.pinsFeedFilterBar)
    }

    func testStableFramesBecomeReadyAndASingleFrameDoesNot() {
        let frame = CGRect(x: 12, y: 40, width: 80, height: 32)
        XCTAssertEqual(
            ContextualTourGeometry.resolve(frame: frame, previous: nil, elapsed: 0.1),
            .waiting
        )
        XCTAssertEqual(
            ContextualTourGeometry.resolve(frame: frame, previous: frame, elapsed: 0.1),
            .ready(frame)
        )
    }

    private var beforeCutoff: Date {
        cutoff.addingTimeInterval(-86_400)
    }

    private var afterCutoff: Date {
        cutoff.addingTimeInterval(86_400)
    }

    private func makeCoordinator() -> ContextualTourCoordinator {
        ContextualTourCoordinator(
            progress: progress,
            cutoff: cutoff,
            schedulesAsyncResolution: false
        )
    }

    private func gates(for surface: ContextualTourSurface) -> ContextualTourGates {
        ContextualTourGates(
            homeRootActive: surface == .dashboard,
            feedRootActive: surface == .feed,
            messagesRootActive: surface == .messages,
            profileRootActive: surface == .profile,
            settingsHomeActive: surface == .settings,
            payoutsActive: surface == .payouts,
            expenseTrackerActive: surface == .expenseTracker,
            tradesActive: surface == .trades,
            sceneActive: true,
            unobstructed: true
        )
    }

    private func arm(_ coordinator: ContextualTourCoordinator, createdAt: Date) {
        coordinator.syncShell(
            userID: "user-a",
            createdAt: createdAt,
            gates: ContextualTourGates(homeRootActive: true, sceneActive: true, unobstructed: true)
        )
    }

    private func presentCurrentStep(_ coordinator: ContextualTourCoordinator) {
        if let step = coordinator.currentStep {
            if step.target == .feedContentFilters {
                coordinator.noteFeedFilterBarLaidOut()
            }
            if step.surface == .settings {
                coordinator.noteSettingsHomeLaidOut()
            }
            coordinator.syncShell(
                userID: "user-a",
                createdAt: afterCutoff,
                gates: gates(for: step.surface)
            )
        }
        let frame = CGRect(x: 24, y: 80, width: 120, height: 44)
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let revision = coordinator.stepRevision
        coordinator.noteMeasuredFrame(frame, viewport: viewport, topInset: 0, bottomInset: 0, revision: revision)
        coordinator.noteMeasuredFrame(
            frame,
            viewport: viewport,
            topInset: 0,
            bottomInset: 0,
            revision: revision
        )
    }

    private func mapSession(createdAt: String?) throws -> SessionBootstrapApplier.Applied {
        var bootstrap = try JSONDecoder().decode(
            SessionBootstrapV1.self,
            from: Data(BackendV2ContractFixtures.session.utf8)
        )
        bootstrap.data.session_profile.created_at = createdAt
        return try SessionBootstrapApplier.mapApplied(bootstrap, expectedViewerID: viewerID)
    }
}
